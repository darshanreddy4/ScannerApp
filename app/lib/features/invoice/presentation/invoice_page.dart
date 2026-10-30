import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/region.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../einvoice/domain/einvoice.dart' show InvoiceParty;
import '../../export/domain/repositories/export_repository.dart';
import '../../importer/domain/importer.dart';
import '../../reader/presentation/reader_page.dart';
import '../data/invoice_pdf.dart';
import '../data/invoice_profile_store.dart';
import '../domain/invoice.dart';
import '../domain/invoice_labels.dart';

const _currencies = ['EUR', 'GBP', 'CHF', 'PLN', 'SEK', 'DKK', 'NOK', 'CZK', 'HUF', 'RON'];

class _ItemFields {
  final description = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final unit = TextEditingController();
  final price = TextEditingController();
  final vat = TextEditingController();

  void dispose() {
    for (final c in [description, quantity, unit, price, vat]) {
      c.dispose();
    }
  }
}

Future<Uint8List> _loadAsset(String path) async => (await rootBundle.load(path)).buffer.asUint8List();

/// Makes an invoice with VAT, IBAN and a SEPA payment QR as a PDF laid out to DIN 5008. Nothing is uploaded.
class InvoicePage extends StatefulWidget {
  const InvoicePage({super.key, this.workDir = getTemporaryDirectory, this.loadAsset = _loadAsset, this.store = const InvoiceProfileStore(), this.now});
  final Future<Directory> Function() workDir;
  final Future<Uint8List> Function(String asset) loadAsset;
  final InvoiceProfileStore store;
  final DateTime? now;

  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  final _sName = TextEditingController();
  final _sStreet = TextEditingController();
  final _sPost = TextEditingController();
  final _sCity = TextEditingController();
  final _sCountry = TextEditingController();
  final _sVat = TextEditingController();
  final _sEmail = TextEditingController();
  final _sIban = TextEditingController();
  final _sBic = TextEditingController();
  final _bName = TextEditingController();
  final _bStreet = TextEditingController();
  final _bPost = TextEditingController();
  final _bCity = TextEditingController();
  final _bCountry = TextEditingController();
  final _bVat = TextEditingController();
  final _number = TextEditingController();
  final _notes = TextEditingController();
  final _items = <_ItemFields>[_ItemFields()];
  late DateTime _issue = widget.now ?? DateTime.now();
  late DateTime _due = _issue.add(const Duration(days: 14));
  int _paymentDays = 14;
  String _currency = 'EUR';
  String? _language;
  bool _reverse = false;
  bool _busy = false;
  String? _made;

  List<TextEditingController> get _all => [
    _sName,
    _sStreet,
    _sPost,
    _sCity,
    _sCountry,
    _sVat,
    _sEmail,
    _sIban,
    _sBic,
    _bName,
    _bStreet,
    _bPost,
    _bCity,
    _bCountry,
    _bVat,
    _number,
    _notes,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await widget.store.load();
    if (!mounted) return;
    final s = profile.seller;
    setState(() {
      _sName.text = s.name;
      _sStreet.text = s.street;
      _sPost.text = s.postcode;
      _sCity.text = s.city;
      _sCountry.text = s.country.isNotEmpty ? s.country : (Region.country ?? '').toUpperCase();
      _sVat.text = s.vatId;
      _sEmail.text = s.email;
      _sIban.text = profile.iban;
      _sBic.text = profile.bic;
      _currency = profile.currency;
      _paymentDays = profile.paymentDays;
      _language = profile.language;
      _number.text = nextInvoiceNumber(profile.lastNumber, _issue);
      _due = _issue.add(Duration(days: _paymentDays));
    });
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  String get _languageCode => _language ?? invoiceLanguageFor(_sCountry.text);

  InvoiceParty _party(
    TextEditingController n,
    TextEditingController st,
    TextEditingController po,
    TextEditingController ci,
    TextEditingController co,
    TextEditingController v, [
    TextEditingController? e,
  ]) => InvoiceParty(
    name: n.text.trim(),
    street: st.text.trim(),
    postcode: po.text.trim(),
    city: ci.text.trim(),
    country: co.text.trim().toUpperCase(),
    vatId: v.text.trim().toUpperCase(),
    email: e?.text.trim() ?? '',
  );

  /// The invoice as typed so far; items with no readable amount are left out and reported by [_itemProblem].
  InvoiceDraft get _draft => InvoiceDraft(
    seller: _party(_sName, _sStreet, _sPost, _sCity, _sCountry, _sVat, _sEmail),
    sellerIban: _sIban.text.trim(),
    sellerBic: _sBic.text.trim(),
    buyer: _party(_bName, _bStreet, _bPost, _bCity, _bCountry, _bVat),
    number: _number.text.trim(),
    issueDate: _issue,
    dueDate: _due,
    currency: _currency,
    items: [
      for (final i in _items)
        if (parseQuantity(i.quantity.text) != null && parseCents(i.price.text) != null)
          InvoiceItem(
            description: i.description.text.trim(),
            quantity: parseQuantity(i.quantity.text)!,
            unit: i.unit.text.trim(),
            unitPriceCents: parseCents(i.price.text)!,
            vatRate: parseVatRate(i.vat.text) ?? 0,
          ),
    ],
    notes: _notes.text,
    reverseCharge: _reverse,
    language: _languageCode,
  );

  String? get _itemProblem {
    for (final (n, i) in _items.indexed) {
      if (parseQuantity(i.quantity.text) == null) return trf('Item {n}: the quantity is not a number above zero.', {'n': n + 1});
      if (parseCents(i.price.text) == null) return trf('Item {n}: the price is not an amount, such as 12.50.', {'n': n + 1});
      if (i.vat.text.trim().isNotEmpty && parseVatRate(i.vat.text) == null) return trf('Item {n}: the VAT rate is not a number from 0 to 100.', {'n': n + 1});
    }
    return null;
  }

  Future<void> _pickDate(bool due) async {
    final initial = due ? _due : _issue;
    final d = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    setState(() {
      if (due) {
        _due = d;
      } else {
        _issue = d;
        _due = d.add(Duration(days: _paymentDays));
      }
      _made = null;
    });
  }

  Future<void> _create() async {
    final problem = _itemProblem ?? invoiceProblem(_draft);
    if (problem != null) {
      showMessage(context, problem);
      return;
    }
    setState(() => _busy = true);
    try {
      final draft = _draft;
      final bytes = await buildInvoicePdf(draft, loadAsset: widget.loadAsset);
      final dir = await Directory(p.join((await widget.workDir()).path, 'invoices')).create(recursive: true);
      final safe = draft.number.replaceAll(RegExp(r'[^\w\-]+'), '_');
      final file = await File(p.join(dir.path, 'Invoice_$safe.pdf')).writeAsBytes(bytes, flush: true);
      await widget.store.save(
        InvoiceProfile(
          seller: draft.seller,
          iban: draft.sellerIban,
          bic: draft.sellerBic,
          currency: _currency,
          paymentDays: _paymentDays,
          lastNumber: draft.number,
          language: _language,
        ),
      );
      if (!mounted) return;
      setState(() {
        _made = file.path;
      });
    } on Object {
      if (mounted) showMessage(context, 'The invoice could not be made. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final r = await sl<ShareService>().shareFile(path: _made!, mimeType: 'application/pdf', subject: p.basename(_made!));
    if (mounted && r.failureOrNull != null) showFailure(context, r.failureOrNull!);
  }

  Widget _tf(
    TextEditingController c,
    String label, {
    TextInputType? keyboard,
    TextCapitalization caps = TextCapitalization.sentences,
    int? maxLength,
    int maxLines = 1,
  }) => TextField(
    controller: c,
    keyboardType: keyboard,
    textCapitalization: caps,
    maxLength: maxLength,
    maxLines: maxLines,
    onChanged: (_) => setState(() => _made = null),
    decoration: InputDecoration(labelText: tr(label), counterText: ''),
  );

  Widget _gap() => const SizedBox(height: AppSpacing.sm + 4);

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    ),
  );

  Widget _itemCard(int index, _ItemFields f, List<double> rates) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    padding: const EdgeInsets.all(AppSpacing.sm + 2),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(AppSpacing.radius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(trf('Item {n}', {'n': index + 1}), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (_items.length > 1)
              IconButton(
                tooltip: tr('Remove item'),
                icon: const Icon(AppIcons.delete, size: 20, color: AppColors.danger),
                onPressed: () => setState(() {
                  _items.removeAt(index).dispose();
                  _made = null;
                }),
              ),
          ],
        ),
        _tf(f.description, 'Description'),
        _gap(),
        Row(
          children: [
            Expanded(child: _tf(f.quantity, 'Quantity', keyboard: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _tf(f.unit, 'Unit (optional)', caps: TextCapitalization.none)),
          ],
        ),
        _gap(),
        Row(
          children: [
            Expanded(child: _tf(f.price, 'Price each, without VAT', keyboard: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _tf(f.vat, _reverse ? 'VAT % (none)' : 'VAT %', keyboard: const TextInputType.numberWithOptions(decimal: true))),
          ],
        ),
        if (!_reverse)
          Wrap(
            spacing: AppSpacing.xs + 2,
            children: [
              for (final r in rates)
                ActionChip(
                  label: Text('${r == r.roundToDouble() ? r.round() : r} %'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    f.vat.text = r == r.roundToDouble() ? '${r.round()}' : '$r';
                    _made = null;
                  }),
                ),
            ],
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final totals = computeTotals(draft.items, reverseCharge: _reverse);
    final country = _sCountry.text.trim().toUpperCase();
    final rates = commonVatRates(country);
    String money(int c) => formatMoney(c, _currency, country: country);
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice maker')),
      body: ListView(
        padding: contentPadding(context),
        children: [
          const Text(
            'Make an invoice with VAT and a payment QR code, laid out to the German DIN 5008 standard that fits a window envelope. Your details are kept on this phone for the next invoice.',
            style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          _section('Your details', [
            _tf(_sName, 'Name or company'),
            _gap(),
            _tf(_sStreet, 'Street and number'),
            _gap(),
            Row(
              children: [
                Expanded(flex: 2, child: _tf(_sPost, 'Postcode', caps: TextCapitalization.characters)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(flex: 3, child: _tf(_sCity, 'Town')),
              ],
            ),
            _gap(),
            Row(
              children: [
                Expanded(child: _tf(_sCountry, 'Country code (DE)', caps: TextCapitalization.characters, maxLength: 2)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(flex: 2, child: _tf(_sVat, 'VAT ID (optional)', caps: TextCapitalization.characters)),
              ],
            ),
            _gap(),
            _tf(_sEmail, 'Email (optional)', keyboard: TextInputType.emailAddress, caps: TextCapitalization.none),
            _gap(),
            _tf(_sIban, 'IBAN (optional)', caps: TextCapitalization.characters),
            _gap(),
            _tf(_sBic, 'BIC (optional)', caps: TextCapitalization.characters),
          ]),
          _section('Customer', [
            _tf(_bName, 'Name or company'),
            _gap(),
            _tf(_bStreet, 'Street and number'),
            _gap(),
            Row(
              children: [
                Expanded(flex: 2, child: _tf(_bPost, 'Postcode', caps: TextCapitalization.characters)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(flex: 3, child: _tf(_bCity, 'Town')),
              ],
            ),
            _gap(),
            Row(
              children: [
                Expanded(child: _tf(_bCountry, 'Country code (DE)', caps: TextCapitalization.characters, maxLength: 2)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(flex: 2, child: _tf(_bVat, 'VAT ID (optional)', caps: TextCapitalization.characters)),
              ],
            ),
          ]),
          _section('Invoice', [
            _tf(_number, 'Invoice number'),
            _gap(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: () => _pickDate(false), child: Text('${tr('Date')}: ${formatDate(_issue)}')),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(onPressed: () => _pickDate(true), child: Text('${tr('Due')}: ${formatDate(_due)}')),
                ),
              ],
            ),
            _gap(),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _currency,
                    decoration: InputDecoration(labelText: tr('Currency')),
                    items: [for (final c in _currencies) DropdownMenuItem(value: c, child: Text(c))],
                    onChanged: (c) => setState(() {
                      _currency = c ?? _currency;
                      _made = null;
                    }),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('lang-$_languageCode'),
                    isExpanded: true,
                    initialValue: _languageCode,
                    decoration: InputDecoration(labelText: tr('Invoice language')),
                    items: [for (final e in InvoiceLabels.supported.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (c) => setState(() {
                      _language = c;
                      _made = null;
                    }),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reverse charge (no VAT)'),
              subtitle: const Text('For business customers in another EU country. The invoice says the customer accounts for the VAT.'),
              value: _reverse,
              onChanged: (v) => setState(() {
                _reverse = v;
                _made = null;
              }),
            ),
          ]),
          _section('Items', [
            for (final (i, f) in _items.indexed) _itemCard(i, f, rates),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _items.add(_ItemFields());
                _made = null;
              }),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add an item'),
            ),
          ]),
          _section('Notes', [_tf(_notes, 'Text under the table (optional)', maxLines: 3)]),
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  _row(tr('Total net'), money(totals.netCents)),
                  if (!_reverse)
                    for (final g in totals.groups) _row('${tr('VAT')} ${g.rate == g.rate.roundToDouble() ? g.rate.round() : g.rate} %', money(g.vatCents)),
                  const Divider(),
                  _row(tr('Amount due'), money(totals.grossCents), strong: true),
                ],
              ),
            ),
          ),
          FilledButton.icon(
            key: const ValueKey('create-invoice'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : _create,
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.pdf, size: 20),
            label: const Text('Create invoice PDF'),
          ),
          if (_made != null) ...[
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.basename(_made!), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        FilledButton.icon(onPressed: _share, icon: const Icon(AppIcons.share, size: 18), label: const Text('Share')),
                        OutlinedButton.icon(
                          onPressed: () => context.push(
                            '/reader',
                            extra: ReaderArgs(path: _made!, kind: ImportKind.pdf),
                          ),
                          icon: const Icon(AppIcons.reader, size: 18),
                          label: const Text('Open'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            tr(
              'Check the VAT rates and wording with your tax adviser. Doculoom lays out what you enter; it does not give tax advice. An invoice made here is a PDF, not an e-invoice for systems that require XML.',
            ),
            style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: TextStyle(fontWeight: strong ? FontWeight.w800 : null)),
        Text(v, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
      ],
    ),
  );
}
