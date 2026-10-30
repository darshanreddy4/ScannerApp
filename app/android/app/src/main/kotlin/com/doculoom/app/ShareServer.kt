package com.doculoom.app

import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.io.RandomAccessFile
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Serves one file over HTTP on the local network behind an unguessable link.
 *
 * It lives in a foreground service, so it keeps answering while the app is minimised or closed. Opening the link
 * always shows a page; the file is only sent when the person taps Download (and, for a protected share, after the
 * password was checked). That keeps link previews and scanner apps from using up a download, and lets the page
 * show progress and a clear "done" message. Every connection is closed after one response so nothing can hang.
 */
class ShareServer(
    private val file: File,
    val fileName: String,
    private val mimeType: String,
    private val password: String?,
    val ttlMillis: Long,
    private val graceMillis: Long = 120_000,
    private val maxWrongAttempts: Int = 5,
    private val now: () -> Long = System::currentTimeMillis,
) {
    val isProtected: Boolean get() = password != null
    val token: String = randomHex(16)

    @Volatile var expiresAt: Long = 0
        private set

    /** Downloads that were sent completely. */
    val downloads: Int get() = downloadCount.get()

    /** True once the time ran out or the sender stopped it; the page then says so for a short while. */
    val ended: Boolean get() = endedFlag.get()

    @Volatile var onChange: (() -> Unit)? = null

    var port: Int = 0
        private set

    private val endedFlag = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val wrongAttempts = AtomicInteger(0)
    private val downloadCount = AtomicInteger(0)
    private val transfers = ConcurrentHashMap<String, Transfer>()
    private val grants = ConcurrentHashMap<String, Long>()
    private val sockets: MutableSet<Socket> = Collections.newSetFromMap(ConcurrentHashMap())
    private val pool = Executors.newCachedThreadPool { r -> Thread(r, "share-conn").apply { isDaemon = true } }
    private val scheduler: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "share-timer").apply { isDaemon = true } }
    private var server: ServerSocket? = null

    private class Transfer(val total: Long) {
        @Volatile var sent: Long = 0
        @Volatile var done: Boolean = false
        @Volatile var counted: Boolean = false
    }

    /** Starts listening and returns the link to share. */
    fun start(host: String): String {
        val s = ServerSocket(0, 50)
        server = s
        port = s.localPort
        expiresAt = now() + ttlMillis
        scheduler.schedule({ end() }, ttlMillis, TimeUnit.MILLISECONDS)
        Thread({ acceptLoop(s) }, "share-accept").apply { isDaemon = true; start() }
        return "http://$host:$port/$token/${encodeName(fileName)}"
    }

    /** Stops handing out the file. The page keeps explaining why for a short while, then the port closes. */
    fun end() {
        if (!endedFlag.compareAndSet(false, true)) return
        onChange?.invoke()
        if (graceMillis <= 0) shutdown() else scheduler.schedule({ shutdown() }, graceMillis, TimeUnit.MILLISECONDS)
    }

    /** Closes the port at once, also for downloads that are still running. */
    fun shutdown() {
        if (endedFlag.compareAndSet(false, true)) onChange?.invoke()
        if (!closed.compareAndSet(false, true)) return
        runCatching { server?.close() }
        sockets.toList().forEach { runCatching { it.close() } }
        pool.shutdownNow()
        scheduler.shutdownNow()
    }

    private fun acceptLoop(s: ServerSocket) {
        while (!s.isClosed) {
            val client = try {
                s.accept()
            } catch (e: IOException) {
                if (s.isClosed) return else continue
            }
            sockets.add(client)
            try {
                pool.execute {
                    try {
                        client.soTimeout = READ_TIMEOUT_MS
                        client.tcpNoDelay = true
                        handle(client)
                    } catch (_: Exception) {
                    } finally {
                        sockets.remove(client)
                        runCatching { client.close() }
                    }
                }
            } catch (_: Exception) {
                sockets.remove(client)
                runCatching { client.close() }
            }
        }
    }

    private class Request(val method: String, val path: String, val query: Map<String, String>, val headers: Map<String, String>, val body: ByteArray)

    private fun handle(socket: Socket) {
        val input = BufferedInputStream(socket.getInputStream())
        val out = socket.getOutputStream()
        val request = readRequest(input) ?: return respondText(out, 400, "Bad request")
        val head = request.method == "HEAD"

        val prefix = "/$token"
        if (request.path != prefix && !request.path.startsWith("$prefix/")) return respondText(out, 404, "Not found", head)
        if (request.method != "GET" && request.method != "HEAD" && request.method != "POST") return respondText(out, 405, "Method not allowed")
        val q = request.query
        // The progress check keeps working after the share ended, so a finished download can still say "done".
        if (request.method != "POST" && q.containsKey("status")) return respondJson(out, 200, statusJson(q["status"].orEmpty()), head)
        if (ended) return respondHtml(out, 410, endedPage(), head)

        when {
            request.method == "POST" && q.containsKey("check") -> checkPassword(out, request)
            request.method == "POST" -> postPassword(out, request)
            q.containsKey("dl") -> download(out, request, head)
            else -> respondHtml(out, 200, landingPage(), head)
        }
    }

    // region password

    private val locked: Boolean get() = wrongAttempts.get() >= maxWrongAttempts

    private fun formPassword(request: Request): String? = try {
        URLDecoder.decode(String(request.body, Charsets.UTF_8).split('&').firstOrNull { it.startsWith("password=") }?.removePrefix("password=").orEmpty(), "UTF-8")
    } catch (_: Exception) {
        null
    }

    /** Constant-time comparison, so response timing reveals nothing about the password. */
    private fun matches(given: String?): Boolean {
        val expected = password ?: return true
        if (given == null) return false
        return MessageDigest.isEqual(given.toByteArray(Charsets.UTF_8), expected.toByteArray(Charsets.UTF_8))
    }

    /** Counts a wrong try and returns how many are left. */
    private fun wrongTry(): Int {
        val used = wrongAttempts.incrementAndGet()
        return (maxWrongAttempts - used).coerceAtLeast(0)
    }

    private fun checkPassword(out: OutputStream, request: Request) {
        if (password == null) return respondJson(out, 200, """{"ok":true,"grant":"${newGrant()}"}""")
        if (locked) return respondJson(out, 403, """{"ok":false,"left":0,"locked":true}""")
        if (matches(formPassword(request))) {
            wrongAttempts.set(0)
            return respondJson(out, 200, """{"ok":true,"grant":"${newGrant()}"}""")
        }
        val left = wrongTry()
        respondJson(out, if (left == 0) 403 else 401, """{"ok":false,"left":$left,"locked":${left == 0}}""")
    }

    /** Fallback for browsers that cannot run the page script: a plain form post that answers with the file. */
    private fun postPassword(out: OutputStream, request: Request) {
        if (password == null) return respondHtml(out, 200, landingPage())
        if (locked) return respondHtml(out, 403, landingPage())
        if (!matches(formPassword(request))) {
            wrongTry()
            return respondHtml(out, if (locked) 403 else 200, landingPage(wrong = true))
        }
        wrongAttempts.set(0)
        sendFile(out, request, newId(), head = false)
    }

    private fun newGrant(): String {
        val grant = randomHex(16)
        val t = now()
        grants.entries.removeAll { it.value < t }
        grants[grant] = t + GRANT_MS
        return grant
    }

    private fun grantOk(grant: String?): Boolean {
        if (password == null) return true
        val until = grant?.let { grants[it] } ?: return false
        return until >= now()
    }

    // endregion

    // region download

    private fun download(out: OutputStream, request: Request, head: Boolean) {
        if (!grantOk(request.query["g"])) return respondHtml(out, 403, landingPage(), head)
        val id = request.query["dl"].orEmpty().takeIf { ID.matches(it) } ?: newId()
        sendFile(out, request, id, head)
    }

    private fun sendFile(out: OutputStream, request: Request, id: String, head: Boolean) {
        val length = file.length()
        var start = 0L
        var end = length - 1
        var partial = false
        val range = request.headers["range"]
        if (range != null) {
            val m = RANGE.matchEntire(range.trim())
            if (m == null) {
                // A range we do not understand is answered with the whole file.
            } else {
                val a = m.groupValues[1]
                val b = m.groupValues[2]
                if (a.isEmpty() && b.isEmpty()) return respondText(out, 416, "Range not satisfiable", head, mapOf("Content-Range" to "bytes */$length"))
                if (a.isEmpty()) {
                    start = (length - b.toLong()).coerceAtLeast(0)
                } else {
                    start = a.toLong()
                    if (b.isNotEmpty()) end = minOf(b.toLong(), length - 1)
                }
                if (start >= length || start > end) return respondText(out, 416, "Range not satisfiable", head, mapOf("Content-Range" to "bytes */$length"))
                partial = true
            }
        }
        val count = end - start + 1
        val headers = linkedMapOf(
            "Content-Type" to mimeType,
            "Content-Length" to count.toString(),
            "Content-Disposition" to "attachment; filename=\"${asciiName()}\"; filename*=UTF-8''${encodeName(fileName)}",
            "Accept-Ranges" to "bytes",
        )
        if (partial) headers["Content-Range"] = "bytes $start-$end/$length"
        writeHead(out, if (partial) 206 else 200, headers)
        if (head) return out.flush()

        val transfer = transfers.getOrPut(id) {
            if (transfers.size > 200) transfers.clear()
            Transfer(length)
        }
        if (start == 0L) transfer.sent = 0
        RandomAccessFile(file, "r").use { raf ->
            raf.seek(start)
            val buffer = ByteArray(64 * 1024)
            var left = count
            while (left > 0) {
                val n = raf.read(buffer, 0, minOf(buffer.size.toLong(), left).toInt())
                if (n < 0) break
                out.write(buffer, 0, n)
                left -= n
                transfer.sent = start + (count - left)
            }
        }
        out.flush()
        // Only a response that reached the last byte of the file counts, and each transfer counts once.
        if (end == length - 1) {
            transfer.done = true
            synchronized(transfer) {
                if (!transfer.counted) {
                    transfer.counted = true
                    downloadCount.incrementAndGet()
                    onChange?.invoke()
                }
            }
        }
    }

    private fun statusJson(id: String): String {
        val t = transfers[id]
        val state = when {
            t == null -> "waiting"
            t.done -> "done"
            else -> "downloading"
        }
        return """{"state":"$state","sent":${t?.sent ?: 0},"total":${t?.total ?: file.length()}}"""
    }

    // endregion

    // region http

    private fun readRequest(input: InputStream): Request? {
        val headBytes = ByteArrayOutputStream()
        var matched = 0
        while (matched < 4) {
            val b = input.read()
            if (b < 0) return null
            headBytes.write(b)
            if (headBytes.size() > MAX_HEAD) return null
            matched = if (b == "\r\n\r\n"[matched].code) matched + 1 else if (b == '\r'.code) 1 else 0
        }
        val lines = headBytes.toString("ISO-8859-1").split("\r\n")
        val parts = lines.firstOrNull()?.split(' ') ?: return null
        if (parts.size < 2) return null
        val headers = HashMap<String, String>()
        for (line in lines.drop(1)) {
            val i = line.indexOf(':')
            if (i > 0) headers[line.substring(0, i).trim().lowercase()] = line.substring(i + 1).trim()
        }
        val target = parts[1]
        val qIndex = target.indexOf('?')
        val path = if (qIndex >= 0) target.substring(0, qIndex) else target
        val query = HashMap<String, String>()
        if (qIndex >= 0) {
            for (pair in target.substring(qIndex + 1).split('&')) {
                if (pair.isEmpty()) continue
                val eq = pair.indexOf('=')
                val key = if (eq >= 0) pair.substring(0, eq) else pair
                val value = if (eq >= 0) pair.substring(eq + 1) else ""
                query[key] = runCatching { URLDecoder.decode(value, "UTF-8") }.getOrDefault("")
            }
        }
        val length = headers["content-length"]?.toIntOrNull() ?: 0
        if (length < 0 || length > MAX_BODY) return null
        val body = ByteArray(length)
        var read = 0
        while (read < length) {
            val n = input.read(body, read, length - read)
            if (n < 0) return null
            read += n
        }
        return Request(parts[0].uppercase(), path, query, headers, body)
    }

    private fun writeHead(out: OutputStream, status: Int, headers: Map<String, String>) {
        val sb = StringBuilder("HTTP/1.1 $status ${reason(status)}\r\n")
        for ((k, v) in headers) sb.append(k).append(": ").append(v).append("\r\n")
        sb.append("Cache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n")
        out.write(sb.toString().toByteArray(Charsets.ISO_8859_1))
    }

    private fun respond(out: OutputStream, status: Int, type: String, body: ByteArray, head: Boolean = false, extra: Map<String, String> = emptyMap()) {
        val headers = linkedMapOf("Content-Type" to type, "Content-Length" to body.size.toString())
        headers.putAll(extra)
        writeHead(out, status, headers)
        if (!head) out.write(body)
        out.flush()
    }

    private fun respondText(out: OutputStream, status: Int, text: String, head: Boolean = false, extra: Map<String, String> = emptyMap()) =
        respond(out, status, "text/plain; charset=utf-8", text.toByteArray(Charsets.UTF_8), head, extra)

    private fun respondJson(out: OutputStream, status: Int, json: String, head: Boolean = false) =
        respond(out, status, "application/json; charset=utf-8", json.toByteArray(Charsets.UTF_8), head)

    private fun respondHtml(out: OutputStream, status: Int, html: String, head: Boolean = false) = respond(
        out, status, "text/html; charset=utf-8", html.toByteArray(Charsets.UTF_8), head,
        mapOf("Content-Security-Policy" to "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; form-action 'self'; frame-ancestors 'none'"),
    )

    private fun reason(status: Int) = when (status) {
        200 -> "OK"
        206 -> "Partial Content"
        400 -> "Bad Request"
        401 -> "Unauthorized"
        403 -> "Forbidden"
        404 -> "Not Found"
        405 -> "Method Not Allowed"
        410 -> "Gone"
        413 -> "Payload Too Large"
        416 -> "Range Not Satisfiable"
        else -> "OK"
    }

    // endregion

    // region pages

    private fun asciiName() = fileName.map { if (it.code in 32..126 && it != '"' && it != '\\') it else '_' }.joinToString("")

    private fun sizeText(bytes: Long): String = when {
        bytes < 1024 * 1024 -> "${maxOf(1, (bytes + 512) / 1024)} kB"
        else -> String.format(java.util.Locale.US, "%.1f MB", bytes / (1024.0 * 1024.0))
    }

    private fun landingPage(wrong: Boolean = false): String {
        val message = when {
            locked -> "Too many wrong attempts. Ask the sender to share the file again."
            wrong -> "Wrong password. ${maxWrongAttempts - wrongAttempts.get()} tries left."
            password != null -> "This file is protected. Enter the password the sender gave you."
            else -> "Tap Download to save this file to your phone."
        }
        val form = if (password != null && !locked) {
            """<form id="form" method="post" autocomplete="off"><input id="pw" type="password" name="password" maxlength="64" placeholder="Password" autocomplete="off"><button id="go" type="submit">Download</button></form>"""
        } else if (password == null) {
            """<a id="go" class="btn" href="?dl=${newId()}">Download</a>"""
        } else {
            ""
        }
        return PAGE
            .replace("{{NAME}}", escape(fileName))
            .replace("{{SIZE}}", sizeText(file.length()))
            .replace("{{MESSAGE}}", escape(message))
            .replace("{{MSGCLASS}}", if (locked || wrong) "msg bad" else "msg")
            .replace("{{FORM}}", form)
            .replace("{{PROTECTED}}", if (password != null) "1" else "0")
    }

    private fun endedPage(): String = PAGE
        .replace("{{NAME}}", escape(fileName))
        .replace("{{SIZE}}", "")
        .replace("{{MESSAGE}}", "This share has ended. Ask the sender to share the file again.")
        .replace("{{MSGCLASS}}", "msg bad")
        .replace("{{FORM}}", "")
        .replace("{{PROTECTED}}", "0")

    // endregion

    companion object {
        private const val READ_TIMEOUT_MS = 20_000
        private const val MAX_HEAD = 16 * 1024
        private const val MAX_BODY = 4 * 1024
        private const val GRANT_MS = 10 * 60 * 1000L
        private val ID = Regex("[A-Za-z0-9_-]{6,40}")
        private val RANGE = Regex("bytes=(\\d*)-(\\d*)")
        private val random = SecureRandom()

        fun randomHex(bytes: Int): String {
            val data = ByteArray(bytes)
            random.nextBytes(data)
            return data.joinToString("") { "%02x".format(it) }
        }

        fun newId(): String = randomHex(8)

        fun escape(text: String): String = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;")

        /** Percent-encodes everything except unreserved characters, like Dart's Uri.encodeComponent for file names. */
        fun encodeName(name: String): String {
            val sb = StringBuilder()
            for (b in name.toByteArray(Charsets.UTF_8)) {
                val c = b.toInt() and 0xff
                if ((c in 'A'.code..'Z'.code) || (c in 'a'.code..'z'.code) || (c in '0'.code..'9'.code) || c == '-'.code || c == '_'.code || c == '.'.code || c == '~'.code) {
                    sb.append(c.toChar())
                } else {
                    sb.append('%').append("%02X".format(c))
                }
            }
            return sb.toString()
        }

        private const val PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex"><title>Download {{NAME}}</title><style>
body{font-family:system-ui,sans-serif;background:#f6f8fb;color:#0f172a;margin:0;min-height:100vh;display:grid;place-items:center}
main{background:#fff;border:1px solid #e2e8f0;border-radius:14px;padding:28px;max-width:400px;width:calc(100% - 40px);text-align:center}
h1{font-size:19px;margin:0 0 4px;word-break:break-word}.size{color:#64748b;font-size:14px;margin:0 0 14px}
.msg{color:#475569;margin:10px 0 16px;line-height:1.45}.bad{color:#b91c1c}.ok{color:#15803d;font-weight:600}
input{width:100%;box-sizing:border-box;padding:12px;border:1px solid #cbd5e1;border-radius:10px;font-size:16px;margin-bottom:12px}
button,.btn{display:block;width:100%;box-sizing:border-box;padding:14px;border:0;border-radius:10px;background:#1d4ed8;color:#fff;font-size:16px;font-weight:600;text-decoration:none;text-align:center}
button:disabled{opacity:.6}.bar{display:none;height:8px;background:#e2e8f0;border-radius:6px;overflow:hidden;margin:6px 0 14px}.bar i{display:block;height:100%;width:0;background:#1d4ed8}
.note{color:#94a3b8;font-size:12px;margin-top:18px}
</style></head><body><main><h1>{{NAME}}</h1><p class="size">{{SIZE}}</p><p id="msg" class="{{MSGCLASS}}">{{MESSAGE}}</p><div id="bar" class="bar"><i id="fill"></i></div>{{FORM}}<p class="note">Shared with Doculoom from a phone on this network.</p></main>
<script>(function(){
var base=location.pathname,protectedShare={{PROTECTED}}===1,msg=document.getElementById('msg'),go=document.getElementById('go'),form=document.getElementById('form'),pw=document.getElementById('pw'),bar=document.getElementById('bar'),fill=document.getElementById('fill');
if(!go||!window.fetch)return;
var timer=null,fails=0,started=0,id='';
function say(text,cls){msg.textContent=text;msg.className='msg'+(cls?' '+cls:'')}
function mb(n){return n<1048576?Math.max(1,Math.round(n/1024))+' kB':(n/1048576).toFixed(1)+' MB'}
function stop(){if(timer){clearInterval(timer);timer=null}}
function poll(){
  fetch(base+'?status='+id,{cache:'no-store'}).then(function(r){if(r.status===410)throw 0;return r.json()}).then(function(s){
    fails=0;
    if(s.state==='done'){stop();bar.style.display='block';fill.style.width='100%';say('Download complete. Find the file in your Downloads or notifications.','ok');go.disabled=false;go.textContent='Download again';return}
    if(s.state==='downloading'){bar.style.display='block';var p=s.total?Math.floor(s.sent*100/s.total):0;fill.style.width=p+'%';say('Downloading '+p+'% ('+mb(s.sent)+' of '+mb(s.total)+')');return}
    if(Date.now()-started>12000){say('The download has not started. Tap Download to try again, and allow downloads if your browser asks.','bad');go.disabled=false;stop()}
  }).catch(function(){
    fails++;
    if(fails>=3){stop();say('Connection lost. The sender may have stopped sharing or left the Wi-Fi. Ask them to share again.','bad');go.disabled=false}
  });
}
function begin(grant){
  id=Math.random().toString(36).slice(2,10)+Date.now().toString(36);started=Date.now();fails=0;
  say('Starting download...');go.disabled=true;
  location.href=base+'?dl='+id+(grant?'&g='+encodeURIComponent(grant):'');
  stop();timer=setInterval(poll,700);
}
if(protectedShare&&form){
  form.addEventListener('submit',function(e){
    e.preventDefault();
    if(!pw.value)return;
    go.disabled=true;say('Checking password...');
    fetch(base+'?check',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'password='+encodeURIComponent(pw.value),cache:'no-store'})
      .then(function(r){return r.json()}).then(function(j){
        if(j.ok){pw.value='';begin(j.grant);return}
        pw.value='';
        if(j.locked){say('Too many wrong attempts. Ask the sender to share the file again.','bad');form.style.display='none';return}
        say('Wrong password. '+j.left+(j.left===1?' try':' tries')+' left.','bad');go.disabled=false;pw.focus();
      }).catch(function(){say('Could not reach the sender. Check that you are on the same Wi-Fi and try again.','bad');go.disabled=false});
  });
}else if(!protectedShare){
  go.addEventListener('click',function(e){e.preventDefault();if(timer)return;begin('')});
}
})();</script></body></html>"""
    }
}
