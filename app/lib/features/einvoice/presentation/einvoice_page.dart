import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../importer/domain/importer.dart';
import '../../qr/domain/payments.dart';
import '../../reader/presentation/reader_page.dart';
import '../data/einvoice_reader.dart';
import '../domain/einvoice.dart';

Future<String?> _pickInvoice() async {
  try {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf', 'xml']);
    return picked.isEmpty ? null : picked.first.path;
  } catch (_) {
    return null;
  }
}

/// Shows an electronic invoice (Factur-X, ZUGFeRD, XRechnung, Peppol, FatturaPA) in plain form. Everything is read on the phone.
class EInvoicePage extends StatefulWidget {
  const EInvoicePage({super.key, this.pick = _pickInvoice});
  final Future<String?> Function() pick;

  @override
  State<EInvoicePage> createState() => _EInvoicePageState();
}

class _EInvoicePageState extends State<EInvoicePage> {
  EInvoiceReadResult? _result;
  String? _path;
  bool _busy = false;

  Future<void> _choose() async {
    final path = await widget.pick();
    if (path == null || !mounted) return;
    setState(() => _busy = true);
    EInvoiceReadResult result;
    try {
      final bytes = await File(path).readAsBytes();
      result = await compute(readEInvoice, bytes);
    } on Object {
      result = const EInvoiceReadResult(problem: 'This file could not be opened.');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _path = path;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final invoice = _result?.invoice;
    return Scaffold(
      appBar: AppBar(title: const Text('E-invoice viewer')),
      body: ListView(
        padding: contentPadding(context),
        children: [
          const Text(
            'Open an electronic invoice: a PDF with invoice data inside (Factur-X, ZUGFeRD) or an XML file (XRechnung, Peppol, FatturaPA). It is read on this phone and not uploaded.',
            style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : _choose,
            icon: const Icon(AppIcons.receipt, size: 20),
            label: Text(invoice == null ? 'Choose an invoice' : 'Choose another invoice'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_result?.problem != null)
            Card(
              margin: const EdgeInsets.only(top: AppSpacing.md),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(tr(_result!.problem!), style: const TextStyle(height: 1.4)),
              ),
            ),
          if (invoice != null) _InvoiceView(invoice: invoice, path: _path!, xmlName: _result!.xmlName),
        ],
      ),
    );
  }
}

class _InvoiceView extends StatelessWidget {
  const _InvoiceView({required this.invoice, required this.path, required this.xmlName});
  final EInvoice invoice;
  final String path;
  final String xmlName;

  String _money(String v) => v.isEmpty ? '' : '$v ${invoice.currency}'.trim();

  Future<void> _copy(BuildContext context, String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showMessage(context, done);
  }

  Widget _kv(String k, String v, {bool strong = false}) => v.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104,
                child: Text(k, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
              ),
              Expanded(
                child: SelectableText(v, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
              ),
            ],
          ),
        );

  Widget _party(String title, InvoiceParty p) => Card(
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 4),
          if (p.isEmpty)
            const Text('Not given')
          else ...[
            _kv(tr('Name'), p.name),
            _kv(tr('VAT ID'), p.vatId),
            _kv(tr('Address'), p.address),
            _kv(tr('Email'), p.email),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    final ibanOk = i.iban.isEmpty || isValidIban(i.iban);
    final canQr = i.currency == 'EUR' && i.iban.isNotEmpty && isValidIban(i.iban) && i.seller.name.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip(label: Text(i.format), visualDensity: VisualDensity.compact),
                    if (i.isCreditNote)
                      Chip(label: const Text('Credit note'), visualDensity: VisualDensity.compact, backgroundColor: AppColors.warning.withValues(alpha: 0.2)),
                  ],
                ),
                _kv(tr('Invoice number'), i.number, strong: true),
                _kv(tr('Date'), i.issueDate == null ? '' : formatDate(i.issueDate!)),
                _kv(tr('Due date'), i.dueDate == null ? '' : formatDate(i.dueDate!)),
                _kv(tr('Currency'), i.currency),
                if (xmlName.isNotEmpty) _kv(tr('Data file'), xmlName),
              ],
            ),
          ),
        ),
        _party(tr('From (seller)'), i.seller),
        _party(tr('To (buyer)'), i.buyer),
        if (i.lines.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trf('Items ({n})', {'n': i.lines.length}),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
                  ),
                  for (final l in i.lines)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.name.isEmpty ? '-' : l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(
                                  [
                                    if (l.quantity.isNotEmpty) '${l.quantity}${l.unit.isEmpty ? '' : ' ${l.unit}'}',
                                    if (l.unitPrice.isNotEmpty) '\u00D7 ${l.unitPrice}',
                                    if (l.vatRate.isNotEmpty) '${l.vatRate}% ${tr('VAT')}',
                                  ].join('  '),
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(l.total, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                _kv(tr('Net total'), _money(i.netTotal)),
                _kv(tr('VAT'), _money(i.taxTotal)),
                _kv(tr('Total'), _money(i.grandTotal), strong: true),
                if (i.amountDue.isNotEmpty && i.amountDue != i.grandTotal) _kv(tr('To pay'), _money(i.amountDue), strong: true),
              ],
            ),
          ),
        ),
        if (i.iban.isNotEmpty || i.paymentReference.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Payment'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
                  ),
                  _kv('IBAN', formatIban(i.iban)),
                  if (!ibanOk)
                    Text(
                      tr('This IBAN does not pass the check. Do not pay before you have checked it.'),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
                    ),
                  _kv('BIC', i.bic),
                  _kv(tr('Reference'), i.paymentReference),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (i.iban.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _copy(context, i.iban, tr('IBAN copied')),
                          icon: const Icon(AppIcons.copy, size: 18),
                          label: const Text('Copy IBAN'),
                        ),
                      if (i.payable.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _copy(context, i.payable, tr('Copied')),
                          icon: const Icon(AppIcons.copy, size: 18),
                          label: const Text('Copy amount'),
                        ),
                      if (i.paymentReference.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _copy(context, i.paymentReference, tr('Copied')),
                          icon: const Icon(AppIcons.copy, size: 18),
                          label: const Text('Copy reference'),
                        ),
                      if (canQr)
                        FilledButton.icon(
                          onPressed: () => context.push(
                            '/qr-payment',
                            extra: SepaPrefill(
                              name: i.seller.name,
                              iban: i.iban,
                              bic: i.bic,
                              amount: i.payable,
                              reference: i.paymentReference.isNotEmpty ? i.paymentReference : i.number,
                            ),
                          ),
                          icon: const Icon(AppIcons.qr, size: 18),
                          label: const Text('Make a payment QR'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (i.notes.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Notes'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
                  ),
                  for (final n in i.notes) Text(n, style: const TextStyle(height: 1.4)),
                ],
              ),
            ),
          ),
        if (path.toLowerCase().endsWith('.pdf'))
          OutlinedButton.icon(
            onPressed: () => context.push(
              '/reader',
              extra: ReaderArgs(path: path, kind: ImportKind.pdf),
            ),
            icon: const Icon(AppIcons.reader, size: 18),
            label: const Text('Open the invoice PDF'),
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          tr('Doculoom shows what the file says. It does not check that the invoice is correct or legally valid.'),
          style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
        ),
      ],
    );
  }
}
