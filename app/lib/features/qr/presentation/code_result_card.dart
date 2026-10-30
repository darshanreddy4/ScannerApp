import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../cards/domain/cards.dart' show CardCodeType;
import '../../cards/presentation/card_edit_page.dart' show CardEditArgs;
import '../../contacts/domain/contact_parser.dart';
import '../../contacts/domain/contact_saver.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../data/system_scan_services.dart' show codeFormatLabel;
import '../domain/qr_payloads.dart' show WifiSecurity;
import '../domain/scan_services.dart';
import '../domain/scanned_code.dart';
import '../domain/upi.dart';

IconData codeKindIcon(CodeKind kind) => switch (kind) {
  CodeKind.link => AppIcons.link,
  CodeKind.wifi => AppIcons.wifi,
  CodeKind.contact => AppIcons.contact,
  CodeKind.email => AppIcons.mail,
  CodeKind.phone => AppIcons.phone,
  CodeKind.sms => AppIcons.message,
  CodeKind.location => AppIcons.mapPin,
  CodeKind.payment => AppIcons.receipt,
  CodeKind.product => AppIcons.barcode,
  CodeKind.text => AppIcons.textLines,
};

String codeKindLabel(CodeKind kind) => switch (kind) {
  CodeKind.link => 'Web link',
  CodeKind.wifi => 'Wi-Fi network',
  CodeKind.contact => 'Contact',
  CodeKind.email => 'Email',
  CodeKind.phone => 'Phone number',
  CodeKind.sms => 'Text message',
  CodeKind.location => 'Location',
  CodeKind.payment => 'Payment',
  CodeKind.product => 'Product barcode',
  CodeKind.text => 'Text',
};

/// Shows what a code holds, with the actions that fit it, in a sheet from the bottom.
Future<void> showCodeSheet(BuildContext context, ScannedCode code) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => SafeArea(
    child: SingleChildScrollView(
      padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640).copyWith(top: 0),
      child: CodeResultCard(code: code),
    ),
  ),
);

class CodeResultCard extends StatefulWidget {
  const CodeResultCard({super.key, required this.code});
  final ScannedCode code;

  @override
  State<CodeResultCard> createState() => _CodeResultCardState();
}

class _CodeResultCardState extends State<CodeResultCard> {
  bool _showPassword = false;

  ScannedCode get code => widget.code;

  Future<void> _copy(String text, [String done = 'Copied']) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showMessage(context, done);
  }

  Future<void> _share() async {
    final r = await sl<ShareService>().shareText(text: code.raw);
    if (mounted && r.failureOrNull != null) showFailure(context, r.failureOrNull!);
  }

  Future<void> _open(String uri, String failure) async {
    final ok = await sl<LinkOpener>().open(uri);
    if (!ok && mounted) showMessage(context, failure);
  }

  static String _encode(Map<String, String?> q) => [
    for (final e in q.entries)
      if ((e.value ?? '').isNotEmpty) '${e.key}=${Uri.encodeComponent(e.value!)}',
  ].join('&');

  static String _dial(String n) => n.replaceAll(RegExp(r'[^\d+]'), '');

  Future<void> _addContact(ContactDraft draft) async {
    final ok = await sl<ContactSaver>().insert(draft);
    if (!ok && mounted) showMessage(context, 'Could not open Contacts on this phone.');
  }

  Future<void> _join(WifiNetwork n) async {
    final result = await sl<WifiJoiner>().join(n);
    if (!mounted) return;
    switch (result) {
      case WifiJoinResult.added:
        showMessage(context, 'Network added. Your phone connects to it when it is in range.');
      case WifiJoinResult.openedSettings:
        if (n.password.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: n.password));
          if (mounted) showMessage(context, 'Wi-Fi settings opened. The password is copied: paste it when asked.');
        } else {
          showMessage(context, 'Wi-Fi settings opened. Choose this network there.');
        }
      case WifiJoinResult.cancelled:
        break;
      case WifiJoinResult.failed:
        showMessage(context, 'This phone could not add the network. Copy the password and join it in Wi-Fi settings.');
    }
  }

  Widget _row(String label, String value, {bool mono = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(fontWeight: FontWeight.w600, fontFamily: mono ? 'monospace' : null),
          ),
        ),
      ],
    ),
  );

  List<Widget> _details() {
    switch (code.kind) {
      case CodeKind.link:
        return [
          SelectableText(code.link!, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35)),
          const SizedBox(height: 6),
          Text(
            code.link!.toLowerCase().startsWith('http://')
                ? 'This link is not encrypted. Check the address before you open it.'
                : trf('Check the address before you open it. It goes to {host}.', {'host': code.host ?? ''}),
            style: TextStyle(fontSize: 12.5, color: code.link!.toLowerCase().startsWith('http://') ? AppColors.warning : AppColors.inkMuted, height: 1.4),
          ),
        ];
      case CodeKind.wifi:
        final w = code.wifi!;
        return [
          _row(tr('Network'), w.ssid),
          _row(tr('Security'), w.security == WifiSecurity.open ? tr('None') : w.security.label),
          if (w.password.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text('Password', style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                  ),
                  Expanded(
                    child: Text(_showPassword ? w.password : '\u2022' * w.password.length.clamp(6, 16), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: tr(_showPassword ? 'Hide password' : 'Show password'),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(_showPassword ? AppIcons.eyeOff : AppIcons.eye, size: 20),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ],
              ),
            ),
          if (w.hidden) _row(tr('Hidden'), tr('Yes')),
        ];
      case CodeKind.contact:
        final c = code.contact!;
        return [
          if (c.name.isNotEmpty) _row(tr('Name'), c.name),
          if (c.organization.isNotEmpty) _row(tr('Company'), c.organization),
          if (c.title.isNotEmpty) _row(tr('Job title'), c.title),
          for (final p in c.phones) _row(tr('Phone'), p),
          for (final e in c.emails) _row(tr('Email'), e),
          for (final w in c.websites) _row(tr('Website'), w),
          if (c.address.isNotEmpty) _row(tr('Address'), c.address),
        ];
      case CodeKind.email:
        return [
          _row(tr('To'), code.address!),
          if ((code.subject ?? '').isNotEmpty) _row(tr('Subject'), code.subject!),
          if ((code.body ?? '').isNotEmpty) _row(tr('Message'), code.body!),
        ];
      case CodeKind.phone:
        return [_row(tr('Number'), code.number!)];
      case CodeKind.sms:
        return [_row(tr('To'), code.number!), if ((code.body ?? '').isNotEmpty) _row(tr('Message'), code.body!)];
      case CodeKind.location:
        return [_row(tr('Latitude'), '${code.latitude}'), _row(tr('Longitude'), '${code.longitude}')];
      case CodeKind.payment:
        final p = code.payment!;
        if (p.isUpi) {
          final problem = upiIdProblem(p.vpa);
          final warning = problem == null ? upiIdWarning(p.vpa) : null;
          return [
            _row(tr('Type'), tr('UPI payment')),
            _row(tr('Pay to'), p.name.isEmpty ? tr('Not given') : p.name),
            _row(tr('UPI ID'), p.vpa, mono: true),
            _row(tr('Amount'), p.amount.isEmpty ? tr('The payer types it') : '\u20B9 ${p.amount}'),
            if (p.currency.isNotEmpty && p.currency != 'INR') _row(tr('Currency'), p.currency),
            if (p.reference.isNotEmpty) _row(tr('Reference'), p.reference),
            if (p.message.isNotEmpty) _row(tr('Note'), p.message),
            if (problem != null || warning != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  tr(problem != null ? 'This UPI ID is not valid. Do not pay before you have checked it.' : warning!),
                  style: TextStyle(fontSize: 12.5, color: problem != null ? AppColors.danger : AppColors.warning, height: 1.4),
                ),
              ),
            Text(
              tr('Scan a UPI code only to pay. You never enter your UPI PIN to receive money: if someone asks for it, it is a scam.'),
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
            ),
          ];
        }
        return [
          _row(tr('Type'), tr(p.scheme == 'SEPA' ? 'SEPA transfer (Girocode)' : 'Swiss QR-bill')),
          _row(tr('Pay to'), p.name),
          if (p.address.isNotEmpty) _row(tr('Address'), p.address),
          _row('IBAN', p.ibanText, mono: true),
          if (p.bic.isNotEmpty) _row('BIC', p.bic),
          if (p.amount.isNotEmpty) _row(tr('Amount'), p.amountText),
          if (p.reference.isNotEmpty) _row(tr('Reference'), p.reference),
          if (p.message.isNotEmpty) _row(tr('Message'), p.message),
          if (!p.ibanValid)
            Text(
              tr('This IBAN does not pass the check. Do not pay before you have checked it.'),
              style: const TextStyle(fontSize: 12.5, color: AppColors.danger, height: 1.4),
            ),
          Text(
            tr('Doculoom does not make payments. Copy the details into your banking app and check them there.'),
            style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
          ),
        ];
      case CodeKind.product:
      case CodeKind.text:
        return [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(child: SelectableText(code.raw, style: const TextStyle(height: 1.4))),
          ),
        ];
    }
  }

  List<Widget> _actions() {
    Widget primary(String label, IconData icon, VoidCallback onTap) => FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
    Widget secondary(String label, IconData icon, VoidCallback onTap) => OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
    final copyAll = secondary('Copy', AppIcons.copy, () => _copy(code.raw));
    final share = secondary('Share', AppIcons.share, _share);
    switch (code.kind) {
      case CodeKind.link:
        return [
          primary('Open link', AppIcons.link, () => _open(code.link!, 'Could not open the link.')),
          secondary('Copy link', AppIcons.copy, () => _copy(code.link!)),
          share,
        ];
      case CodeKind.wifi:
        final w = code.wifi!;
        return [
          primary('Join network', AppIcons.wifi, () => _join(w)),
          if (w.password.isNotEmpty)
            secondary('Copy password', AppIcons.copy, () => _copy(w.password))
          else
            secondary('Copy name', AppIcons.copy, () => _copy(w.ssid)),
        ];
      case CodeKind.contact:
        return [primary('Add contact', AppIcons.contact, () => _addContact(code.contact!)), copyAll, share];
      case CodeKind.email:
        final q = _encode({'subject': code.subject, 'body': code.body});
        return [
          primary('Write email', AppIcons.mail, () => _open('mailto:${code.address}${q.isEmpty ? '' : '?$q'}', 'Could not open an email app.')),
          secondary('Copy address', AppIcons.copy, () => _copy(code.address!)),
          share,
        ];
      case CodeKind.phone:
        return [
          primary('Call', AppIcons.phone, () => _open('tel:${_dial(code.number!)}', 'Could not open the phone app.')),
          secondary('Send message', AppIcons.message, () => _open('sms:${_dial(code.number!)}', 'Could not open a messaging app.')),
          secondary('Add contact', AppIcons.contact, () => _addContact(ContactDraft(phones: [code.number!]))),
          secondary('Copy number', AppIcons.copy, () => _copy(code.number!)),
        ];
      case CodeKind.sms:
        final q = _encode({'body': code.body});
        return [
          primary('Send message', AppIcons.message, () => _open('sms:${_dial(code.number!)}${q.isEmpty ? '' : '?$q'}', 'Could not open a messaging app.')),
          secondary('Copy number', AppIcons.copy, () => _copy(code.number!)),
        ];
      case CodeKind.payment:
        final p = code.payment!;
        if (p.isUpi) {
          return [
            primary('Pay with a UPI app', AppIcons.receipt, () => _open(code.raw, 'No UPI app was found on this phone.')),
            secondary('Copy UPI ID', AppIcons.copy, () => _copy(p.vpa, 'UPI ID copied')),
            if (p.amount.isNotEmpty) secondary('Copy amount', AppIcons.copy, () => _copy(p.amount)),
            secondary('Copy all details', AppIcons.copy, () => _copy([p.name, p.vpa, p.amountText, p.message].where((s) => s.isNotEmpty).join('\n'))),
          ];
        }
        return [
          primary('Copy IBAN', AppIcons.copy, () => _copy(p.iban, 'IBAN copied')),
          if (p.amount.isNotEmpty) secondary('Copy amount', AppIcons.copy, () => _copy(p.amount)),
          if (p.reference.isNotEmpty || p.message.isNotEmpty)
            secondary('Copy reference', AppIcons.copy, () => _copy(p.reference.isNotEmpty ? p.reference : p.message)),
          secondary(
            'Copy all details',
            AppIcons.copy,
            () => _copy([p.name, p.ibanText, p.amountText, p.reference, p.message].where((s) => s.isNotEmpty).join('\n')),
          ),
        ];
      case CodeKind.location:
        return [
          primary('Open in maps', AppIcons.mapPin, () async {
            final ok = await sl<LinkOpener>().open(code.geoUri!);
            if (!ok) await _open('https://www.google.com/maps?q=${code.latitude},${code.longitude}', 'Could not open a maps app.');
          }),
          secondary('Copy coordinates', AppIcons.copy, () => _copy(code.summary)),
        ];
      case CodeKind.product:
      case CodeKind.text:
        return [
          copyAll,
          secondary(
            'Save as a card',
            AppIcons.cards,
            () => context.push<String>(
              '/card-edit',
              extra: CardEditArgs(number: code.raw, type: CardCodeType.fromScan(code.format)),
            ),
          ),
          share,
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final format = codeFormatLabel(code.format);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Icon(codeKindIcon(code.kind), size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(codeKindLabel(code.kind), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  if (format.isNotEmpty) Text(format, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ..._details(),
        const SizedBox(height: AppSpacing.md),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: _actions()),
      ],
    );
  }
}
