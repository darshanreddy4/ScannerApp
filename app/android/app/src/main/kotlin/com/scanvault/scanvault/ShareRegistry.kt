package com.scanvault.scanvault

import java.io.File
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * Every share that is running in this process. It outlives the Flutter screen and engine, so closing the app
 * screen does not stop a share; only its timer, "Stop sharing" or the notification action does.
 */
object ShareRegistry {
    class Entry(val id: String, val server: ShareServer, val url: String, val dir: File, val fileName: String)

    private val entries = LinkedHashMap<String, Entry>()
    private var baseDir: File? = null

    @Volatile var listener: (() -> Unit)? = null

    @Synchronized
    fun init(dir: File) {
        baseDir = dir
        dir.mkdirs()
        // A copy left behind by a process that was killed is no longer served by anyone.
        dir.listFiles()?.filter { it.name !in entries }?.forEach { it.deleteRecursively() }
    }

    /** Copies the file (the app may delete its own temporary copy) and starts serving it. */
    fun start(source: File, fileName: String, mimeType: String, ttlMillis: Long, password: String?, host: String): Entry {
        val root = synchronized(this) { checkNotNull(baseDir) { "Share storage is not ready" } }
        val id = ShareServer.newId()
        val dir = File(root, id).apply { mkdirs() }
        try {
            val copy = File(dir, "file")
            source.copyTo(copy, overwrite = true)
            val server = ShareServer(copy, fileName, mimeType, password, ttlMillis)
            val url = server.start(host)
            val entry = Entry(id, server, url, dir, fileName)
            synchronized(this) { entries[id] = entry }
            server.onChange = { changed(entry) }
            listener?.invoke()
            return entry
        } catch (e: Exception) {
            dir.deleteRecursively()
            throw e
        }
    }

    private fun changed(entry: Entry) {
        if (entry.server.ended) {
            synchronized(this) { entries.remove(entry.id) }
            entry.dir.deleteRecursively()
        }
        listener?.invoke()
    }

    @Synchronized fun list(): List<Entry> = entries.values.filter { !it.server.ended }

    @Synchronized fun get(id: String): Entry? = entries[id]

    fun stop(id: String) {
        get(id)?.server?.end()
    }

    fun stopAll() {
        list().forEach { it.server.end() }
    }

    /** The phone's address on the Wi-Fi it is joined to, or the one it hands out as a hotspot. */
    fun lanAddress(): String? {
        val interfaces = NetworkInterface.getNetworkInterfaces() ?: return null
        for (nic in interfaces) {
            if (!nic.isUp || nic.isLoopback || nic.isVirtual) continue
            for (address in nic.inetAddresses) {
                if (address is Inet4Address && address.isSiteLocalAddress) return address.hostAddress
            }
        }
        return null
    }
}
