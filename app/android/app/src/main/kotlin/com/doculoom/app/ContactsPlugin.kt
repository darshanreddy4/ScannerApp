package com.doculoom.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Email
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.provider.ContactsContract.CommonDataKinds.Website
import android.provider.ContactsContract.Intents.Insert
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Opens the Contacts app's "new contact" screen with the details filled in. The person confirms the save there,
 * so this app needs no contacts permission and never reads the address book.
 */
class ContactsPlugin(private val activity: Activity, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "doculoom/contacts").setMethodCallHandler { call, result ->
            if (call.method == "insert") {
                result.success(insert(call.arguments as? Map<*, *> ?: emptyMap<String, Any>()))
            } else {
                result.notImplemented()
            }
        }
    }

    private fun text(v: Any?): String = (v as? String)?.trim() ?: ""

    private fun list(v: Any?): List<String> = (v as? List<*>)?.mapNotNull { (it as? String)?.trim()?.takeIf { s -> s.isNotEmpty() } } ?: emptyList()

    private fun insert(a: Map<*, *>): Boolean {
        val intent = Intent(Insert.ACTION).apply { type = ContactsContract.RawContacts.CONTENT_TYPE }
        text(a["name"]).takeIf { it.isNotEmpty() }?.let { intent.putExtra(Insert.NAME, it) }
        text(a["organization"]).takeIf { it.isNotEmpty() }?.let { intent.putExtra(Insert.COMPANY, it) }
        text(a["title"]).takeIf { it.isNotEmpty() }?.let { intent.putExtra(Insert.JOB_TITLE, it) }
        text(a["address"]).takeIf { it.isNotEmpty() }?.let { intent.putExtra(Insert.POSTAL, it) }

        // The first three numbers and emails have their own fields; the rest and the websites travel as data rows.
        val phones = list(a["phones"])
        val emails = list(a["emails"])
        val extra = ArrayList<ContentValues>()
        val phoneKeys = listOf(Insert.PHONE, Insert.SECONDARY_PHONE, Insert.TERTIARY_PHONE)
        val emailKeys = listOf(Insert.EMAIL, Insert.SECONDARY_EMAIL, Insert.TERTIARY_EMAIL)
        phones.forEachIndexed { i, n ->
            if (i < phoneKeys.size) intent.putExtra(phoneKeys[i], n)
            else extra.add(ContentValues().apply { put(ContactsContract.Data.MIMETYPE, Phone.CONTENT_ITEM_TYPE); put(Phone.NUMBER, n) })
        }
        emails.forEachIndexed { i, e ->
            if (i < emailKeys.size) intent.putExtra(emailKeys[i], e)
            else extra.add(ContentValues().apply { put(ContactsContract.Data.MIMETYPE, Email.CONTENT_ITEM_TYPE); put(Email.ADDRESS, e) })
        }
        list(a["websites"]).forEach { w ->
            extra.add(ContentValues().apply { put(ContactsContract.Data.MIMETYPE, Website.CONTENT_ITEM_TYPE); put(Website.URL, w) })
        }
        if (extra.isNotEmpty()) intent.putParcelableArrayListExtra(Insert.DATA, extra)
        // Returns to this app once the contact is saved.
        intent.putExtra("finishActivityOnSaveCompleted", true)
        return try {
            activity.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }
}
