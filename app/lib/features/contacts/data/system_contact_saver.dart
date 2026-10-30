import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../domain/contact_parser.dart';
import '../domain/contact_saver.dart';

/// Hands the details to Android's Contacts app, which asks the person to confirm. No contacts permission is needed.
class SystemContactSaver implements ContactSaver {
  const SystemContactSaver();

  static const _channel = MethodChannel('doculoom/contacts');

  @override
  Future<bool> insert(ContactDraft draft) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('insert', {
            'name': draft.name,
            'organization': draft.organization,
            'title': draft.title,
            'phones': draft.phones,
            'emails': draft.emails,
            'websites': draft.websites,
            'address': draft.address,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
