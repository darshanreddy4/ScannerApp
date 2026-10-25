import assert from 'node:assert/strict';
import { test } from 'node:test';
import worker, { sweep } from '../src/index.js';

class FakeBucket {
  items = new Map();
  async put(key, value, options) {
    this.items.set(key, { body: new Uint8Array(value), customMetadata: options?.customMetadata ?? {} });
  }
  async get(key) {
    const item = this.items.get(key);
    return item && { body: item.body, size: item.body.length, customMetadata: item.customMetadata };
  }
  async head(key) {
    const item = this.items.get(key);
    return item && { customMetadata: item.customMetadata };
  }
  async delete(keys) {
    for (const k of Array.isArray(keys) ? keys : [keys]) this.items.delete(k);
  }
  async list() {
    return { objects: [...this.items].map(([key, v]) => ({ key, customMetadata: v.customMetadata })), truncated: false };
  }
}

const b64url = (bytes) => Buffer.from(bytes).toString('base64url');

// Same layout as the app: nonce(12) + ciphertext + tag(16), key in the link fragment.
async function seal(plain) {
  const raw = crypto.getRandomValues(new Uint8Array(32));
  const key = await crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt']);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, plain));
  return { payload: Buffer.concat([iv, sealed]), key: b64url(raw) };
}

// Password shares: the key is derived with PBKDF2-SHA256 from the password and a salt carried in the link.
async function sealWithPassword(plain, password, iterations = 100000) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveKey']);
  const key = await crypto.subtle.deriveKey({ name: 'PBKDF2', salt, iterations, hash: 'SHA-256' }, base, { name: 'AES-GCM', length: 256 }, false, ['encrypt']);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, plain));
  return { payload: Buffer.concat([iv, sealed]), salt: b64url(salt), iterations };
}

async function open(payload, keyText) {
  const key = await crypto.subtle.importKey('raw', Buffer.from(keyText, 'base64url'), 'AES-GCM', false, ['decrypt']);
  return new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: payload.slice(0, 12) }, key, payload.slice(12)));
}

function env(extra = {}) {
  return { FILES: new FakeBucket(), ...extra };
}

async function post(e, body, ttl) {
  const headers = { 'content-length': String(body.length), 'content-type': 'application/octet-stream' };
  if (ttl !== undefined) headers['x-ttl'] = String(ttl);
  return worker.fetch(new Request('https://relay.test/api/upload', { method: 'POST', headers, body }), e);
}

test('an uploaded file downloads and decrypts with the key from the link', async () => {
  const e = env();
  const plain = new TextEncoder().encode('%PDF-1.7 contract');
  const { payload, key } = await seal(plain);

  const up = await post(e, payload, 900);
  assert.equal(up.status, 200);
  const { id, expiresAt } = await up.json();
  assert.match(id, /^[A-Za-z0-9_-]{22}$/);
  assert.ok(expiresAt - Date.now() > 890_000 && expiresAt - Date.now() <= 900_000);

  const down = await worker.fetch(new Request(`https://relay.test/api/file/${id}`), e);
  assert.equal(down.status, 200);
  const stored = new Uint8Array(await down.arrayBuffer());
  assert.deepEqual(stored, new Uint8Array(payload));
  assert.deepEqual(await open(stored, key), plain);
});

test('the lifetime is limited to 7 days and at least one minute', async () => {
  const e = env();
  const { payload } = await seal(new Uint8Array(10));
  const long = await (await post(e, payload, 99 * 24 * 3600)).json();
  assert.ok(long.expiresAt - Date.now() <= 7 * 24 * 3600 * 1000);
  const short = await (await post(e, payload, 1)).json();
  assert.ok(short.expiresAt - Date.now() >= 59_000);
});

test('oversized and empty uploads are refused', async () => {
  const e = env({ MAX_BYTES: '1000' });
  assert.equal((await post(e, new Uint8Array(2000))).status, 413);
  const noLength = await worker.fetch(new Request('https://relay.test/api/upload', { method: 'POST', body: new Uint8Array(0) }), e);
  assert.equal(noLength.status, 411);
});

test('an expired file answers 410 and is removed', async () => {
  const e = env();
  const { payload } = await seal(new Uint8Array(10));
  const { id } = await (await post(e, payload, 60)).json();
  e.FILES.items.get(id).customMetadata.expiresAt = String(Date.now() - 1);

  const res = await worker.fetch(new Request(`https://relay.test/api/file/${id}`), e);
  assert.equal(res.status, 410);
  assert.equal(e.FILES.items.has(id), false);
});

test('only the holder of the delete token can remove a file', async () => {
  const e = env();
  const { payload } = await seal(new Uint8Array(10));
  const { id, deleteToken } = await (await post(e, payload)).json();

  const wrong = await worker.fetch(new Request(`https://relay.test/api/file/${id}`, { method: 'DELETE', headers: { 'x-delete-token': 'nope' } }), e);
  assert.equal(wrong.status, 403);
  assert.equal(e.FILES.items.has(id), true);

  const ok = await worker.fetch(new Request(`https://relay.test/api/file/${id}`, { method: 'DELETE', headers: { 'x-delete-token': deleteToken } }), e);
  assert.equal(ok.status, 200);
  assert.equal(e.FILES.items.has(id), false);
});

test('malformed ids and unknown paths are not found', async () => {
  const e = env();
  assert.equal((await worker.fetch(new Request('https://relay.test/api/file/..%2Fsecret'), e)).status, 404);
  assert.equal((await worker.fetch(new Request('https://relay.test/api/file/short'), e)).status, 404);
  assert.equal((await worker.fetch(new Request('https://relay.test/nothing'), e)).status, 404);
});

test('the hourly sweep deletes only expired files', async () => {
  const e = env();
  const { payload } = await seal(new Uint8Array(10));
  const a = await (await post(e, payload, 3600)).json();
  const b = await (await post(e, payload, 3600)).json();
  e.FILES.items.get(a.id).customMetadata.expiresAt = String(Date.now() - 5);

  assert.equal(await sweep(e), 1);
  assert.equal(e.FILES.items.has(a.id), false);
  assert.equal(e.FILES.items.has(b.id), true);
});

test('the download page is locked down and never shows the key to the server', async () => {
  const e = env();
  const res = await worker.fetch(new Request('https://relay.test/d/abcdefghijklmnopqrstuv'), e);
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-security-policy'), /script-src 'self'/);
  assert.equal(res.headers.get('referrer-policy'), 'no-referrer');
  const html = await res.text();
  assert.ok(html.includes('/app.js'));

  const js = await (await worker.fetch(new Request('https://relay.test/app.js'), e)).text();
  assert.ok(js.includes('location.hash'), 'the key is read from the fragment');
  assert.ok(!/fetch\([^)]*keyText/.test(js), 'the key is not sent to the server');
});

// Runs the real page script against a minimal browser stand-in, with the payload layout the app produces.
async function runPage({ payload, hash, status = 200 }) {
  const dom = {
    title: { textContent: '' },
    status: { textContent: '' },
    download: { style: {}, textContent: '', href: '', download: '' },
    form: { style: {}, onsubmit: null },
    password: { value: '' },
    submit: { disabled: false },
  };
  const elements = { title: dom.title, status: dom.status, download: dom.download, form: dom.form, password: dom.password, submit: dom.submit };
  const globals = {
    document: { getElementById: (id) => elements[id] },
    location: { pathname: '/d/abcdefghijklmnopqrstuv', hash },
    window: { crypto },
    crypto,
    atob: (t) => Buffer.from(t, 'base64').toString('binary'),
    TextEncoder,
    Math,
    parseInt,
    URLSearchParams,
    Uint8Array,
    Blob,
    URL: { createObjectURL: (blob) => ({ blob }) },
    encodeURIComponent,
    fetch: async () => ({ status, ok: status === 200, arrayBuffer: async () => payload.buffer.slice(payload.byteOffset, payload.byteOffset + payload.byteLength) }),
  };
  const { PAGE_JS } = await import('../src/page.js');
  const fn = new Function(...Object.keys(globals), `${PAGE_JS}\nreturn new Promise((r) => setTimeout(r, 50));`);
  await fn(...Object.values(globals));
  return dom;
}

test('the download page decrypts the file in the browser and offers it for download', async () => {
  const plain = new TextEncoder().encode('hello scanned world');
  const { payload, key } = await seal(plain);
  const dom = await runPage({ payload, hash: `#k=${key}&n=contract.pdf&t=application%2Fpdf` });
  assert.equal(dom.title.textContent, 'Your file is ready');
  assert.equal(dom.download.download, 'contract.pdf');
  assert.equal(dom.download.style.display, 'inline-block');
  assert.equal(Buffer.from(await dom.download.href.blob.arrayBuffer()).toString(), 'hello scanned world');
});

test('the download page explains a missing key, a wrong key and an expired file', async () => {
  const { payload } = await seal(new Uint8Array(40));
  const noKey = await runPage({ payload, hash: '' });
  assert.match(noKey.status.textContent, /incomplete/);

  const other = await seal(new Uint8Array(40));
  const wrong = await runPage({ payload, hash: `#k=${other.key}` });
  assert.match(wrong.status.textContent, /not valid/);

  const gone = await runPage({ payload, hash: `#k=${other.key}`, status: 410 });
  assert.match(gone.status.textContent, /expired/);
});

test('a password share asks for the password, rejects a wrong one and opens with the right one', async () => {
  const plain = new TextEncoder().encode('secret contract');
  const { payload, salt, iterations } = await sealWithPassword(plain, 'correct horse battery');
  const dom = await runPage({ payload, hash: `#p=1&s=${salt}&i=${iterations}&n=deal.pdf&t=application%2Fpdf` });

  assert.equal(dom.title.textContent, 'Password needed');
  assert.equal(dom.form.style.display, 'block');
  assert.equal(dom.download.style.display, undefined, 'nothing is offered before the password');

  dom.password.value = 'wrong guess';
  await dom.form.onsubmit({ preventDefault() {} });
  assert.match(dom.status.textContent, /Wrong password/);
  assert.equal(dom.download.style.display, undefined);
  assert.equal(dom.submit.disabled, false);

  dom.password.value = 'correct horse battery';
  await dom.form.onsubmit({ preventDefault() {} });
  assert.equal(dom.title.textContent, 'Your file is ready');
  assert.equal(dom.download.download, 'deal.pdf');
  assert.equal(Buffer.from(await dom.download.href.blob.arrayBuffer()).toString(), 'secret contract');
});

test('a link with a password marker but no salt is reported as incomplete', async () => {
  const { payload } = await seal(new Uint8Array(40));
  const dom = await runPage({ payload, hash: '#p=1&n=x.pdf' });
  assert.match(dom.status.textContent, /incomplete/);
});
