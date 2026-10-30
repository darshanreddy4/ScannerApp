import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../domain/contact_parser.dart';
import '../domain/contact_saver.dart';
import '../domain/vcard.dart';
import '../../../core/widgets/text.dart';

List<String> _lines(String text) => [
  for (final l in text.split(RegExp(r'[\r\n]+')))
    if (l.trim().isNotEmpty) l.trim(),
];

String contactFileName(String name) {
  final safe = name.replaceAll(RegExp(r'[^\p{L}\p{N}\- ]+', unicode: true), '').trim().replaceAll(RegExp(r'\s+'), '_');
  return '${safe.isEmpty ? 'contact' : safe}.vcf';
}

/// Shows what was read from a business card, lets it be corrected, and hands it to the phone's Contacts app as a vCard.
class ContactPage extends StatefulWidget {
  const ContactPage({super.key, required this.text, this.workDir = getTemporaryDirectory});

  /// The text recognised on the card.
  final String text;
  final Future<Directory> Function() workDir;

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  late final ContactDraft _read = parseContactText(widget.text);
  late final _name = TextEditingController(text: _read.name);
  late final _org = TextEditingController(text: _read.organization);
  late final _title = TextEditingController(text: _read.title);
  late final _phones = TextEditingController(text: _read.phones.join('\n'));
  late final _emails = TextEditingController(text: _read.emails.join('\n'));
  late final _sites = TextEditingController(text: _read.websites.join('\n'));
  late final _address = TextEditingController(text: _read.address);

  @override
  void dispose() {
    for (final c in [_name, _org, _title, _phones, _emails, _sites, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  ContactDraft get _draft => ContactDraft(
    name: _name.text.trim(),
    organization: _org.text.trim(),
    title: _title.text.trim(),
    phones: _lines(_phones.text),
    emails: _lines(_emails.text),
    websites: _lines(_sites.text),
    address: _address.text.trim(),
  );

  /// The details to send on, or null (with a message) when there is nothing to send.
  ContactDraft? _ready() {
    final draft = _draft;
    if (draft.isEmpty) {
      showMessage(context, 'Add a name, a phone number or an email first.');
      return null;
    }
    return draft;
  }

  Future<void> _save() async {
    final draft = _ready();
    if (draft == null) return;
    if (await sl<ContactSaver>().insert(draft) || !mounted) return;
    showMessage(context, 'No Contacts app could be opened, so the contact file is shared instead.');
    await _share();
  }

  Future<void> _share() async {
    final draft = _ready();
    if (draft == null) return;
    final dir = await Directory(p.join((await widget.workDir()).path, 'exports')).create(recursive: true);
    final name = contactFileName(draft.name.isEmpty ? (draft.emails.isNotEmpty ? draft.emails.first.split('@').first : '') : draft.name);
    final file = await File(p.join(dir.path, name)).writeAsString(buildVCard(draft), flush: true);
    final failure = (await sl<ShareService>().shareFile(path: file.path, mimeType: 'text/vcard', subject: draft.name)).failureOrNull;
    if (failure != null && mounted) showFailure(context, failure);
  }

  Future<void> _copy() async {
    final d = _draft;
    final text = [d.name, d.title, d.organization, ...d.phones, ...d.emails, ...d.websites, d.address].where((s) => s.isNotEmpty).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showMessage(context, 'Details copied');
  }

  Widget _field(String key, String label, TextEditingController c, {int lines = 1, IconData? icon, TextInputType? type}) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm + 4),
    child: TextField(
      key: ValueKey(key),
      controller: c,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 2,
      keyboardType: type ?? (lines > 1 ? TextInputType.multiline : TextInputType.text),
      decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon, size: 20)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final found = !_read.isUsable;
    return Scaffold(
      appBar: AppBar(title: const Text('Contact from card')),
      body: SafeArea(
        child: ListView(
          padding: contentPadding(context, base: AppSpacing.md, maxWidth: 560),
          children: [
            Container(
              key: const ValueKey('contact-note'),
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: found ? const Color(0xFFFFF7E0) : const Color(0xFFEFF4FF),
                borderRadius: BorderRadius.circular(AppSpacing.radius),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(AppIcons.info, size: 18, color: found ? const Color(0xFF8A6100) : AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      found
                          ? 'No name, number or email was found in this text. Type the details below, or scan the card again with good light.'
                          : 'Check what was read from the card and correct anything that is wrong, then save it to your Contacts.',
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            _field('contact-name', 'Name', _name, icon: AppIcons.person),
            _field('contact-title', 'Job title', _title),
            _field('contact-org', 'Company', _org),
            _field('contact-phones', 'Phone numbers (one per line)', _phones, lines: 2, icon: AppIcons.phone, type: TextInputType.phone),
            _field('contact-emails', 'Emails (one per line)', _emails, lines: 2, icon: AppIcons.mail, type: TextInputType.emailAddress),
            _field('contact-sites', 'Websites (one per line)', _sites, icon: AppIcons.link, type: TextInputType.url),
            _field('contact-address', 'Address', _address, lines: 2),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              key: const ValueKey('contact-save'),
              onPressed: _save,
              icon: const Icon(AppIcons.person, size: 18),
              label: const Text('Save to phone contacts'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const ValueKey('contact-share'),
              onPressed: _share,
              icon: const Icon(AppIcons.share, size: 18),
              label: const Text('Share contact file'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const ValueKey('contact-copy'),
              onPressed: _copy,
              icon: const Icon(AppIcons.copy, size: 18),
              label: const Text('Copy details'),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Save to phone contacts opens your Contacts app with these details filled in; you confirm the save there. Nothing is uploaded.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
