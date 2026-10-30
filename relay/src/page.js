// Download page. The decryption key is in the URL fragment (#k=...), which browsers never send to a server.
export const PAGE_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta name="referrer" content="no-referrer">
<title>Download file</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f6f8fb; color: #0f172a; }
  main { background: #fff; border: 1px solid #e2e8f0; border-radius: 14px; padding: 28px; max-width: 420px; width: calc(100% - 40px); text-align: center; }
  h1 { font-size: 20px; margin: 0 0 8px; }
  p { color: #64748b; line-height: 1.45; margin: 8px 0; }
  form { display: none; margin-top: 16px; }
  input { width: 100%; box-sizing: border-box; padding: 12px; border: 1px solid #cbd5e1; border-radius: 10px; font-size: 16px; margin-bottom: 12px; }
  button { width: 100%; padding: 13px; border: 0; border-radius: 10px; background: #1d4ed8; color: #fff; font-size: 16px; font-weight: 600; }
  button:disabled { opacity: .6; }
  a.button { display: none; margin-top: 16px; padding: 14px 20px; border-radius: 10px; background: #1d4ed8; color: #fff; text-decoration: none; font-weight: 600; word-break: break-word; }
</style>
</head>
<body>
<main>
  <h1 id="title">Preparing your file</h1>
  <p id="status">Decrypting on your device...</p>
  <form id="form">
    <input id="password" type="password" autocomplete="off" placeholder="Password" maxlength="64">
    <button id="submit" type="submit">Open</button>
  </form>
  <a id="download" class="button" href="#">Download</a>
  <p>Shared with Doculoom. The file is end-to-end encrypted; this service cannot read it.</p>
</main>
<script src="/app.js"></script>
</body>
</html>`;

export const PAGE_JS = `(function () {
  var title = document.getElementById('title');
  var status = document.getElementById('status');
  var link = document.getElementById('download');
  var form = document.getElementById('form');
  var passwordInput = document.getElementById('password');
  var submit = document.getElementById('submit');

  function fail(message) {
    title.textContent = 'Cannot open this file';
    status.textContent = message;
  }

  function fromBase64Url(text) {
    var base64 = text.replace(/-/g, '+').replace(/_/g, '/');
    while (base64.length % 4) base64 += '=';
    var raw = atob(base64);
    var bytes = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
    return bytes;
  }

  function sizeText(bytes) {
    if (bytes < 1024 * 1024) return Math.max(1, Math.round(bytes / 1024)) + ' kB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }

  function show(plain, name, type) {
    var url = URL.createObjectURL(new Blob([plain], { type: type }));
    form.style.display = 'none';
    title.textContent = 'Your file is ready';
    status.textContent = name + ' (' + sizeText(plain.byteLength) + ')';
    link.href = url;
    link.download = name;
    link.textContent = 'Download';
    link.style.display = 'inline-block';
    link.onclick = function () {
      title.textContent = 'Download started';
      status.textContent = name + ' is being saved to your device. Check your notifications or Downloads folder.';
      link.textContent = 'Download again';
    };
  }

  async function decrypt(data, key) {
    return crypto.subtle.decrypt({ name: 'AES-GCM', iv: data.slice(0, 12) }, key, data.slice(12));
  }

  // The key comes from the password with PBKDF2, repeated as many times as the app did.
  async function keyFromPassword(password, salt, iterations) {
    var base = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveKey']);
    return crypto.subtle.deriveKey({ name: 'PBKDF2', salt: salt, iterations: iterations, hash: 'SHA-256' }, base, { name: 'AES-GCM', length: 256 }, false, ['decrypt']);
  }

  function askPassword(data, params, name, type) {
    var salt = fromBase64Url(params.get('s'));
    var iterations = Math.min(5000000, Math.max(100000, parseInt(params.get('i'), 10) || 300000));
    title.textContent = 'Password needed';
    status.textContent = 'Enter the password the sender gave you.';
    form.style.display = 'block';
    form.onsubmit = async function (event) {
      event.preventDefault();
      if (!passwordInput.value) return;
      submit.disabled = true;
      status.textContent = 'Checking password...';
      try {
        var key = await keyFromPassword(passwordInput.value, salt, iterations);
        show(await decrypt(data, key), name, type);
      } catch (e) {
        status.textContent = 'Wrong password. Try again.';
        passwordInput.value = '';
        submit.disabled = false;
      }
    };
  }

  async function run() {
    if (!window.crypto || !crypto.subtle) return fail('Open this link in an up-to-date browser (it must be https).');
    var id = location.pathname.split('/').pop();
    var params = new URLSearchParams(location.hash.slice(1));
    var keyText = params.get('k');
    var withPassword = params.get('p') === '1' && !!params.get('s');
    if (!keyText && !withPassword) return fail('This link is incomplete. Ask the sender to share it again.');
    var name = params.get('n') || 'document';
    var type = params.get('t') || 'application/octet-stream';

    var response = await fetch('/api/file/' + encodeURIComponent(id));
    if (response.status === 404 || response.status === 410) return fail('This file has expired or was removed by the sender.');
    if (!response.ok) return fail('The file could not be downloaded. Please try again.');

    var data = new Uint8Array(await response.arrayBuffer());
    if (data.length < 29) return fail('The file is damaged.');
    if (withPassword) return askPassword(data, params, name, type);
    var key = await crypto.subtle.importKey('raw', fromBase64Url(keyText), 'AES-GCM', false, ['decrypt']);
    var plain;
    try {
      plain = await decrypt(data, key);
    } catch (e) {
      return fail('The link is not valid for this file. Ask the sender to share it again.');
    }
    show(plain, name, type);
  }

  run().catch(function () { fail('Something went wrong. Please try again.'); });
})();`;
