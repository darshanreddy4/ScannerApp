import { PAGE_HTML, PAGE_JS } from './page.js';

const DEFAULT_MAX_BYTES = 25 * 1024 * 1024;
const MIN_TTL = 60;
const MAX_TTL = 7 * 24 * 3600;
const DEFAULT_TTL = 300;
// 12-byte nonce + 16-byte GCM tag added by the app around the file.
const CRYPTO_OVERHEAD = 28;
const ID_PATTERN = /^[A-Za-z0-9_-]{22}$/;

const BASE_HEADERS = {
  'Cache-Control': 'no-store',
  'Referrer-Policy': 'no-referrer',
  'X-Content-Type-Options': 'nosniff',
};

const PAGE_HEADERS = {
  ...BASE_HEADERS,
  'Content-Security-Policy':
    "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  'X-Robots-Tag': 'noindex, nofollow',
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...BASE_HEADERS, 'Content-Type': 'application/json' } });
}

function randomId(bytes = 16) {
  const data = crypto.getRandomValues(new Uint8Array(bytes));
  return btoa(String.fromCharCode(...data)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function sameSecret(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function upload(request, env) {
  const maxBytes = Number(env.MAX_BYTES) || DEFAULT_MAX_BYTES;
  const limit = maxBytes + CRYPTO_OVERHEAD;
  const length = Number(request.headers.get('content-length'));
  if (!Number.isFinite(length) || length <= 0) return json({ error: 'length_required' }, 411);
  if (length > limit) return json({ error: 'too_large' }, 413);

  const requested = Number(request.headers.get('x-ttl'));
  const ttl = Math.min(MAX_TTL, Math.max(MIN_TTL, Number.isFinite(requested) && requested > 0 ? Math.floor(requested) : DEFAULT_TTL));

  const body = await request.arrayBuffer();
  if (body.byteLength === 0 || body.byteLength > limit) return json({ error: 'too_large' }, 413);

  const id = randomId(16);
  const deleteToken = randomId(16);
  const expiresAt = Date.now() + ttl * 1000;
  await env.FILES.put(id, body, { customMetadata: { expiresAt: String(expiresAt), token: deleteToken } });
  return json({ id, deleteToken, expiresAt });
}

async function download(id, env) {
  const object = await env.FILES.get(id);
  if (!object) return json({ error: 'not_found' }, 404);
  if (Number(object.customMetadata?.expiresAt) <= Date.now()) {
    await env.FILES.delete(id);
    return json({ error: 'expired' }, 410);
  }
  return new Response(object.body, {
    headers: { ...BASE_HEADERS, 'Content-Type': 'application/octet-stream', 'Content-Length': String(object.size) },
  });
}

async function remove(id, request, env) {
  const object = await env.FILES.head(id);
  if (!object) return json({ ok: true });
  if (!sameSecret(object.customMetadata?.token, request.headers.get('x-delete-token'))) return json({ error: 'forbidden' }, 403);
  await env.FILES.delete(id);
  return json({ ok: true });
}

export async function sweep(env, now = Date.now()) {
  let cursor;
  let removed = 0;
  do {
    const page = await env.FILES.list({ cursor, include: ['customMetadata'] });
    const expired = page.objects.filter((o) => Number(o.customMetadata?.expiresAt) <= now).map((o) => o.key);
    if (expired.length) {
      await env.FILES.delete(expired);
      removed += expired.length;
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return removed;
}

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);

    if (request.method === 'POST' && pathname === '/api/upload') return upload(request, env);

    const fileMatch = pathname.match(/^\/api\/file\/([^/]+)$/);
    if (fileMatch) {
      const id = fileMatch[1];
      if (!ID_PATTERN.test(id)) return json({ error: 'not_found' }, 404);
      if (request.method === 'GET') return download(id, env);
      if (request.method === 'DELETE') return remove(id, request, env);
    }

    const pageMatch = pathname.match(/^\/d\/([^/]+)$/);
    if (request.method === 'GET' && pageMatch) {
      return new Response(PAGE_HTML, { headers: { ...PAGE_HEADERS, 'Content-Type': 'text/html; charset=utf-8' } });
    }
    if (request.method === 'GET' && pathname === '/app.js') {
      return new Response(PAGE_JS, { headers: { ...BASE_HEADERS, 'Content-Type': 'text/javascript; charset=utf-8' } });
    }
    if (request.method === 'GET' && pathname === '/') {
      return new Response('ScanVault share relay', { headers: { ...BASE_HEADERS, 'Content-Type': 'text/plain' } });
    }
    return json({ error: 'not_found' }, 404);
  },

  async scheduled(_event, env) {
    await sweep(env);
  },
};
