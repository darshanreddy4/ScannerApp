package com.scanvault.scanvault

import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicInteger
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class ShareServerTest {
    private lateinit var dir: File
    private lateinit var file: File
    private val bytes = ByteArray(300_000) { (it % 251).toByte() }
    private var server: ShareServer? = null

    @Before
    fun setUp() {
        dir = File.createTempFile("share", "dir").also { it.delete(); it.mkdirs() }
        file = File(dir, "file").also { it.writeBytes(bytes) }
    }

    @After
    fun tearDown() {
        server?.shutdown()
        dir.deleteRecursively()
    }

    private class Reply(val code: Int, val body: ByteArray, val headers: Map<String, String>) {
        val text: String get() = String(body, Charsets.UTF_8)
    }

    private fun start(password: String? = null, ttl: Long = 60_000, grace: Long = 60_000, name: String = "My report.pdf"): String {
        val s = ShareServer(file, name, "application/pdf", password, ttl, grace)
        server = s
        return s.start("127.0.0.1")
    }

    private fun call(url: String, method: String = "GET", body: String? = null, headers: Map<String, String> = emptyMap()): Reply {
        val c = URL(url).openConnection() as HttpURLConnection
        c.requestMethod = method
        c.connectTimeout = 5000
        c.readTimeout = 10000
        c.instanceFollowRedirects = false
        headers.forEach { (k, v) -> c.setRequestProperty(k, v) }
        if (body != null) {
            c.doOutput = true
            c.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            c.outputStream.use { it.write(body.toByteArray()) }
        }
        val code = c.responseCode
        val stream = if (code >= 400) c.errorStream else c.inputStream
        val out = ByteArrayOutputStream()
        stream?.use { it.copyTo(out) }
        val h = c.headerFields.filterKeys { it != null }.mapKeys { it.key.lowercase() }.mapValues { it.value.joinToString(",") }
        return Reply(code, out.toByteArray(), h)
    }

    private fun waitFor(ms: Long = 3000, check: () -> Boolean) {
        val end = System.currentTimeMillis() + ms
        while (!check() && System.currentTimeMillis() < end) Thread.sleep(20)
    }

    @Test
    fun `opening the link shows a page and does not use up a download`() {
        val url = start()
        val page = call(url)
        assertEquals(200, page.code)
        assertTrue(page.text.contains("My report.pdf"))
        assertTrue(page.text.contains("Download"))
        assertFalse("a page view must not send the file", page.text.length > 50_000)
        assertEquals(0, server!!.downloads)
        // Scanner apps and chat previews may open the link several times.
        call(url, "HEAD")
        call(url)
        assertEquals(0, server!!.downloads)
    }

    @Test
    fun `tapping download sends the whole file once and the status says done`() {
        val url = start()
        val changes = AtomicInteger()
        server!!.onChange = { changes.incrementAndGet() }

        assertTrue(call("$url?status=abc123def").text.contains("waiting"))
        val file = call("$url?dl=abc123def")
        assertEquals(200, file.code)
        assertTrue(bytes.contentEquals(file.body))
        assertTrue(file.headers["content-disposition"]!!.contains("attachment"))
        assertEquals("application/pdf", file.headers["content-type"])
        assertEquals("bytes", file.headers["accept-ranges"])
        assertEquals(1, server!!.downloads)
        assertTrue(changes.get() >= 1)
        assertTrue(call("$url?status=abc123def").text.contains("\"done\""))

        // The same transfer repeated (for example a resumed download) is still one download.
        call("$url?dl=abc123def")
        assertEquals(1, server!!.downloads)
        call("$url?dl=another-id-1")
        assertEquals(2, server!!.downloads)
    }

    @Test
    fun `a range request is answered partially and only counts when it reaches the end`() {
        val url = start()
        val part = call("$url?dl=range-one", headers = mapOf("Range" to "bytes=100-199"))
        assertEquals(206, part.code)
        assertEquals("bytes 100-199/${bytes.size}", part.headers["content-range"])
        assertTrue(bytes.copyOfRange(100, 200).contentEquals(part.body))
        assertEquals(0, server!!.downloads)

        val tail = call("$url?dl=range-one", headers = mapOf("Range" to "bytes=${bytes.size - 10}-"))
        assertEquals(206, tail.code)
        assertEquals(1, server!!.downloads)

        assertEquals(416, call("$url?dl=range-two", headers = mapOf("Range" to "bytes=${bytes.size + 5}-")).code)
    }

    @Test
    fun `a download the browser abandons is not counted`() {
        val big = ByteArray(40 * 1024 * 1024)
        file.writeBytes(big)
        val url = start()
        val c = URL("$url?dl=abandon-1").openConnection() as HttpURLConnection
        c.inputStream.use { it.read(ByteArray(1024)) }
        c.disconnect()
        Thread.sleep(600)
        assertEquals(0, server!!.downloads)
        assertTrue(call("$url?status=abandon-1").text.contains("downloading"))
    }

    @Test
    fun `unknown paths and wrong tokens look like missing pages`() {
        val url = start()
        val base = url.substringBefore("/${server!!.token}")
        assertEquals(404, call("$base/").code)
        assertEquals(404, call("$base/favicon.ico").code)
        assertEquals(404, call("$base/${"0".repeat(32)}/My%20report.pdf").code)
        assertEquals(405, call(url, "DELETE").code)
    }

    @Test
    fun `a protected share needs the password and gives a grant for the download`() {
        val url = start(password = "open-sesame")
        val page = call(url)
        assertTrue(page.text.contains("type=\"password\""))

        // The file is not handed out without a grant.
        assertEquals(403, call("$url?dl=need-grant-1").code)
        assertEquals(0, server!!.downloads)

        val wrong = call("$url?check", "POST", "password=nope")
        assertEquals(401, wrong.code)
        assertTrue(wrong.text.contains("\"left\":4"))
        assertTrue(wrong.text.contains("\"ok\":false"))

        val right = call("$url?check", "POST", "password=open-sesame")
        assertEquals(200, right.code)
        val grant = Regex("\"grant\":\"([0-9a-f]+)\"").find(right.text)!!.groupValues[1]
        val file = call("$url?dl=with-grant-1&g=$grant")
        assertEquals(200, file.code)
        assertTrue(bytes.contentEquals(file.body))
        assertEquals(1, server!!.downloads)

        assertEquals(403, call("$url?dl=with-grant-2&g=${"0".repeat(32)}").code)
    }

    @Test
    fun `five wrong passwords lock the share, even for the right password`() {
        val url = start(password = "open-sesame")
        repeat(4) { assertEquals(401, call("$url?check", "POST", "password=bad$it").code) }
        val last = call("$url?check", "POST", "password=bad9")
        assertEquals(403, last.code)
        assertTrue(last.text.contains("\"locked\":true"))
        assertEquals(403, call("$url?check", "POST", "password=open-sesame").code)
        assertTrue(call(url).text.contains("Too many wrong attempts"))
    }

    @Test
    fun `a right password resets the wrong-try count`() {
        val url = start(password = "open-sesame")
        repeat(3) { call("$url?check", "POST", "password=bad$it") }
        assertEquals(200, call("$url?check", "POST", "password=open-sesame").code)
        assertTrue(call("$url?check", "POST", "password=bad").text.contains("\"left\":4"))
    }

    @Test
    fun `the plain form still works without scripts`() {
        val url = start(password = "open-sesame")
        val wrong = call(url, "POST", "password=wrong")
        assertEquals(200, wrong.code)
        assertTrue(wrong.text.contains("Wrong password"))
        val ok = call(url, "POST", "password=open-sesame")
        assertEquals(200, ok.code)
        assertTrue(bytes.contentEquals(ok.body))
        assertEquals(1, server!!.downloads)
    }

    @Test
    fun `passwords with special characters are compared exactly`() {
        val url = start(password = "p@ss word&=é")
        val encoded = java.net.URLEncoder.encode("p@ss word&=é", "UTF-8")
        assertEquals(200, call("$url?check", "POST", "password=$encoded").code)
    }

    @Test
    fun `after the share ends the page explains it, then the port closes`() {
        val url = start(grace = 400)
        server!!.end()
        val gone = call(url)
        assertEquals(410, gone.code)
        assertTrue(gone.text.contains("This share has ended"))
        assertEquals(410, call("$url?dl=late-one-1").code)
        Thread.sleep(900)
        try {
            call(url)
            throw AssertionError("the port should be closed")
        } catch (_: java.io.IOException) {
        }
    }

    @Test
    fun `the timer ends the share by itself`() {
        val url = start(ttl = 300, grace = 60_000)
        val ended = AtomicInteger()
        server!!.onChange = { if (server!!.ended) ended.incrementAndGet() }
        waitFor { server!!.ended }
        assertTrue(server!!.ended)
        assertEquals(410, call(url).code)
        assertTrue(ended.get() >= 1)
    }

    @Test
    fun `file names with spaces and non ASCII letters make a valid link and header`() {
        val url = start(name = "Spurti Prakash Biodata (final) ü.pdf")
        assertTrue(url.endsWith("/Spurti%20Prakash%20Biodata%20%28final%29%20%C3%BC.pdf"))
        val file = call("$url?dl=name-test-1")
        assertEquals(200, file.code)
        assertTrue(file.headers["content-disposition"]!!.contains("filename*=UTF-8''Spurti%20Prakash"))
    }

    @Test
    fun `the page escapes the file name`() {
        val url = start(name = "<script>alert(1)</script>.pdf")
        val text = call(url).text
        assertFalse(text.contains("<script>alert(1)"))
        assertTrue(text.contains("&lt;script&gt;"))
    }

    @Test
    fun `many people can download at the same time`() {
        val url = start()
        val threads = (1..6).map { i ->
            Thread {
                val r = call("$url?dl=parallel-$i")
                assertTrue(bytes.contentEquals(r.body))
            }.also { it.start() }
        }
        threads.forEach { it.join(10_000) }
        waitFor { server!!.downloads == 6 }
        assertEquals(6, server!!.downloads)
    }

    @Test
    fun `a stalled connection does not block other downloads`() {
        val url = start()
        // Opens a connection and sends nothing, like a browser that stalled.
        val stalled = java.net.Socket("127.0.0.1", server!!.port)
        try {
            assertEquals(200, call(url).code)
            assertEquals(200, call("$url?dl=after-stall-1").code)
        } finally {
            stalled.close()
        }
    }
}
