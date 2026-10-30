import 'contact_parser.dart';

abstract interface class ContactSaver {
  /// Opens the phone's own "new contact" screen filled in with [draft]; false when this phone cannot do that.
  Future<bool> insert(ContactDraft draft);
}
