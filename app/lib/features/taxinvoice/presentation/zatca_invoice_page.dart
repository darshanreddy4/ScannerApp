import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../invoice/domain/invoice.dart' show parseCents, parseQuantity;
import '../../pdf_tools/presentation/pdf_result_card.dart';
import '../data/tax_profile_store.dart';
import '../data/zatca_pdf.dart';
import '../domain/tax_common.dart';
import '../domain/us_invoice.dart' show nextUsInvoiceNumber;
import '../domain/zatca.dart';
import 'form_kit.dart';

Future<Uint8List> _loadAsset(String path) async => (await rootBundle.load(path)).buffer.asUint8List();

class _Item {
  final description = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final price = TextEditingController();
  final discount = TextEditingController();
  VatCategory category = VatCategory.standard;

  void dispose() {
    for (final c in [description, quantity, price, discount]) {
      c.dispose();
    }
  }
}

/// Makes a Saudi tax invoice or simplified tax invoice in Arabic and English, with VAT at 15 percent and the first-phase QR code.
/// It does not connect to ZATCA, so it is not a second-phase (integration) e-invoice.
class ZatcaInvoicePage extends StatefulWidget {
  const ZatcaInvoicePage({
    super.key,
    this.workDir = getTemporaryDirectory,
    this.loadAsset = _loadAsset,
    this.store = const TaxProfileStore(zatcaProfileKey),
    this.now,
  });
  final Future<Directory> Function() workDir;
  final Future<Uint8List> Function(String asset) loadAsset;
  final TaxProfileStore store;
  final DateTime? now;

  @override
  State<ZatcaInvoicePage> createState() => _ZatcaInvoicePageState();
}

class _ZatcaInvoicePageState extends State<ZatcaInvoicePage> {
  final _sName = TextEditingController();
  final _sVat = TextEditingController();
  final _sAddress = TextEditingController();
  final _sDistrict = TextEditingController();
  final _sCity = TextEditingController();
  final _sPost = TextEditingController();
  final _sCr = TextEditingController();
  final _bName = TextEditingController();
  final _bVat = TextEditingController();
  final _bAddress = TextEditingController();
  final _bCity = TextEditingController();
  final _bPost = TextEditingController();
  final _number = TextEditingController();
  final _notes = TextEditingController();
  final _items = <_Item>[_Item()];
  ZatcaDocument _doc = ZatcaDocument.simplified;
  bool _inclusive = false;
  bool _submitted = false;
  bool _busy = false;
  String? _made;
  late DateTime _issued = _minute(widget.now ?? DateTime.now());

  static DateTime _minute(DateTime d) => DateTime(d.year, d.month, d.day, d.hour, d.minute);

  List<TextEditingController> get _all => [
    _sName,
    _sVat,
    _sAddress,
    _sDistrict,
    _sCity,
    _sPost,
    _sCr,
    _bName,
    _bVat,
    _bAddress,
    _bCity,
    _bPost,
    _number,
    _notes,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _sName.text = v['name'] ?? '';
      _sVat.text = v['vat'] ?? '';
      _sAddress.text = v['address'] ?? '';
      _sDistrict.text = v['district'] ?? '';
      _sCity.text = v['city'] ?? '';
      _sPost.text = v['postcode'] ?? '';
      _sCr.text = v['cr'] ?? '';
      _number.text = nextUsInvoiceNumber(v['lastNumber'] ?? '');
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

  int? _cents(String text) => text.trim().isEmpty ? 0 : parseCents(text);

  ZatcaDraft get _draft => ZatcaDraft(
    document: _doc,
    seller: ZatcaParty(
      name: _sName.text,
      vat: _sVat.text,
      address: _sAddress.text,
      district: _sDistrict.text,
      city: _sCity.text,
      postcode: _sPost.text,
      cr: _sCr.text,
    ),
    buyer: ZatcaParty(name: _bName.text, vat: _bVat.text, address: _bAddress.text, city: _bCity.text, postcode: _bPost.text),
    number: _number.text,
    issuedAt: _issued,
    items: [
      for (final i in _items)
        ZatcaLine(
          description: i.description.text,
          quantity: parseQuantity(i.quantity.text) ?? 0,
          unitPriceCents: parseCents(i.price.text) ?? 0,
          discountCents: _cents(i.discount.text) ?? 0,
          category: i.category,
        ),
    ],
    pricesIncludeVat: _inclusive,
    notes: _notes.text,
  );

  List<TaxIssue> get _issueList {
    final out = <TaxIssue>[];
    for (final (n, i) in _items.indexed) {
      if (parseQuantity(i.quantity.text) == null) out.add(TaxIssue('item.$n.quantity', 'Item {n}: the quantity must be a number above zero.', {'n': n + 1}));
      if (parseCents(i.price.text) == null) out.add(TaxIssue('item.$n.price', 'Item {n}: the price must be an amount, for example 125.50.', {'n': n + 1}));
      if (_cents(i.discount.text) == null) out.add(TaxIssue('item.$n.discount', 'Item {n}: the discount must be an amount such as 10.00.', {'n': n + 1}));
    }
    return [...out, ...zatcaIssues(_draft)];
  }

  void _changed() => setState(() => _made = null);

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _issued, firstDate: DateTime(2021, 12, 4), lastDate: DateTime(2100));
    if (d != null && mounted) {
      setState(() {
        _issued = DateTime(d.year, d.month, d.day, _issued.hour, _issued.minute);
        _made = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _issued.hour, minute: _issued.minute),
    );
    if (t != null && mounted) {
      setState(() {
        _issued = DateTime(_issued.year, _issued.month, _issued.day, t.hour, t.minute);
        _made = null;
      });
    }
  }

  Future<void> _create() async {
    setState(() => _submitted = true);
    if (_issueList.isNotEmpty) {
      showMessage(context, 'Fix the marked fields, then try again.');
      return;
    }
    setState(() => _busy = true);
    try {
      final d = _draft;
      final bytes = await buildZatcaPdf(d, loadAsset: widget.loadAsset);
      final dir = await Directory(p.join((await widget.workDir()).path, 'invoices')).create(recursive: true);
      final safe = d.number.trim().replaceAll(RegExp(r'[^\w\-]+'), '_');
      final file = await File(p.join(dir.path, 'Saudi_$safe.pdf')).writeAsBytes(bytes, flush: true);
      await widget.store.save({
        'name': _sName.text.trim(),
        'vat': _sVat.text.trim(),
        'address': _sAddress.text.trim(),
        'district': _sDistrict.text.trim(),
        'city': _sCity.text.trim(),
        'postcode': _sPost.text.trim(),
        'cr': _sCr.text.trim(),
        'lastNumber': d.number.trim(),
      });
      if (mounted) setState(() => _made = file.path);
    } on Object {
      if (mounted) showMessage(context, 'The invoice could not be made. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _itemCard(int n, _Item f, Map<String, TaxIssue> issues) {
    TaxIssue? at(String k) => _submitted ? issues['item.$n.$k'] : null;
    return Container(
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
                child: Text(trf('Item {n}', {'n': n + 1}), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (_items.length > 1)
                IconButton(
                  key: ValueKey('sa-remove-$n'),
                  tooltip: tr('Remove item'),
                  icon: const Icon(AppIcons.delete, size: 20, color: AppColors.danger),
                  onPressed: () => setState(() {
                    _items.removeAt(n).dispose();
                    _made = null;
                  }),
                ),
            ],
          ),
          TaxField(controller: f.description, label: 'Description *', onChanged: _changed, issue: at('description')),
          taxGap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TaxField(controller: f.quantity, label: 'Quantity *', onChanged: _changed, issue: at('quantity'), keyboard: decimalKeyboard),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: TaxField(
                  controller: f.price,
                  label: _inclusive ? 'Price each, with VAT *' : 'Price each, before VAT *',
                  onChanged: _changed,
                  issue: at('price'),
                  keyboard: decimalKeyboard,
                  prefix: 'SAR ',
                ),
              ),
            ],
          ),
          taxGap,
          TaxField(
            controller: f.discount,
            label: 'Discount on this item (optional)',
            onChanged: _changed,
            issue: at('discount'),
            keyboard: decimalKeyboard,
            prefix: 'SAR ',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (c, label) in [(VatCategory.standard, 'VAT 15%'), (VatCategory.zero, 'Zero-rated 0%'), (VatCategory.exempt, 'Exempt')])
                ChoiceChip(
                  key: ValueKey('sa-vat-$n-${c.name}'),
                  label: Text(label),
                  selected: f.category == c,
                  onSelected: (_) => setState(() {
                    f.category = c;
                    _made = null;
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summary(ZatcaDraft d) {
    final t = computeZatca(d);
    String money(int c) => 'SAR ${groupWestern(c)}';
    Widget row(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontWeight: strong ? FontWeight.w700 : FontWeight.w400)),
          ),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(fontWeight: strong ? FontWeight.w700 : FontWeight.w400)),
        ],
      ),
    );
    return Container(
      key: const ValueKey('sa-summary'),
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppSpacing.radius)),
      child: Column(
        children: [row(tr('Taxable amount'), money(t.taxable)), row(tr('VAT'), money(t.vat)), const Divider(), row(tr('Total'), money(t.total), strong: true)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final issues = issuesByField(_issueList);
    TaxIssue? at(String k) => _submitted ? issues[k] : null;
    final standard = _doc == ZatcaDocument.standard;
    return Scaffold(
      appBar: AppBar(title: const Text('Saudi VAT invoice')),
      body: ListView(
        padding: contentPadding(context).copyWith(bottom: AppSpacing.xl),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Container(
            key: const ValueKey('sa-notice'),
            padding: const EdgeInsets.all(AppSpacing.sm + 4),
            decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(AppSpacing.radius)),
            child: const Text(
              'This makes an invoice in Arabic and English with VAT at 15% and the first-phase QR code. It does not connect to ZATCA, so it cannot do the second phase of e-invoicing (Fatoora integration), which ZATCA brings in by waves. Check whether your business must use a ZATCA-approved system.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF78350F), height: 1.4),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<ZatcaDocument>(
            key: const ValueKey('sa-document'),
            segments: const [
              ButtonSegment(value: ZatcaDocument.simplified, label: Text('Simplified')),
              ButtonSegment(value: ZatcaDocument.standard, label: Text('Tax invoice')),
            ],
            selected: {_doc},
            onSelectionChanged: (s) => setState(() {
              _doc = s.first;
              _made = null;
            }),
          ),
          const SizedBox(height: 6),
          Text(
            standard
                ? 'For a customer that is a VAT-registered business. It needs their VAT number and address.'
                : 'For a consumer sale. It carries the QR code.',
            key: const ValueKey('sa-document-hint'),
            style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          TaxSection(
            title: 'Your business',
            hint: 'Write the name as it is on your VAT registration, in Arabic or English.',
            children: [
              TaxField(controller: _sName, label: 'Business name *', onChanged: _changed, issue: at('seller.name'), caps: TextCapitalization.words),
              taxGap,
              TaxField(
                controller: _sVat,
                label: 'VAT registration number *',
                onChanged: _changed,
                issue: at('seller.vat'),
                helper: '15 digits, starting and ending with 3.',
                keyboard: TextInputType.number,
                caps: TextCapitalization.none,
                maxLength: 15,
              ),
              taxGap,
              TaxField(controller: _sAddress, label: 'Building number and street *', onChanged: _changed, issue: at('seller.address')),
              taxGap,
              TaxField(controller: _sDistrict, label: 'District', onChanged: _changed),
              taxGap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TaxField(controller: _sCity, label: 'City *', onChanged: _changed, issue: at('seller.city'), caps: TextCapitalization.words),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TaxField(
                      controller: _sPost,
                      label: 'Postal code',
                      onChanged: _changed,
                      issue: at('seller.postcode'),
                      keyboard: TextInputType.number,
                      caps: TextCapitalization.none,
                      maxLength: 5,
                    ),
                  ),
                ],
              ),
              taxGap,
              TaxField(
                controller: _sCr,
                label: 'Commercial registration no. (optional)',
                onChanged: _changed,
                keyboard: TextInputType.number,
                caps: TextCapitalization.none,
              ),
            ],
          ),
          TaxSection(
            title: 'Customer',
            children: [
              TaxField(
                controller: _bName,
                label: standard ? 'Customer name *' : 'Customer name (optional)',
                onChanged: _changed,
                issue: at('buyer.name'),
                caps: TextCapitalization.words,
              ),
              taxGap,
              TaxField(
                controller: _bVat,
                label: standard ? 'Customer VAT number *' : 'Customer VAT number (optional)',
                onChanged: _changed,
                issue: at('buyer.vat'),
                keyboard: TextInputType.number,
                caps: TextCapitalization.none,
                maxLength: 15,
              ),
              taxGap,
              TaxField(controller: _bAddress, label: standard ? 'Address *' : 'Address (optional)', onChanged: _changed, issue: at('buyer.address')),
              taxGap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TaxField(controller: _bCity, label: 'City', onChanged: _changed, caps: TextCapitalization.words),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TaxField(
                      controller: _bPost,
                      label: 'Postal code',
                      onChanged: _changed,
                      issue: at('buyer.postcode'),
                      keyboard: TextInputType.number,
                      caps: TextCapitalization.none,
                      maxLength: 5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          TaxSection(
            title: 'Invoice details',
            children: [
              TaxField(
                controller: _number,
                label: 'Invoice number *',
                onChanged: _changed,
                issue: at('number'),
                caps: TextCapitalization.characters,
                maxLength: 20,
              ),
              taxGap,
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('sa-date'),
                      onPressed: _pickDate,
                      icon: const Icon(AppIcons.timer, size: 18),
                      label: Text(formatDate(_issued)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton(
                    key: const ValueKey('sa-time'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(72, 48)),
                    onPressed: _pickTime,
                    child: Text('${_issued.hour.toString().padLeft(2, '0')}:${_issued.minute.toString().padLeft(2, '0')}'),
                  ),
                ],
              ),
              SwitchListTile(
                key: const ValueKey('sa-inclusive'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Prices include VAT'),
                subtitle: const Text('The prices you type already have the 15% in them'),
                value: _inclusive,
                onChanged: (v) => setState(() {
                  _inclusive = v;
                  _made = null;
                }),
              ),
            ],
          ),
          TaxSection(
            title: 'Items',
            children: [
              if (at('items') != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(at('items')!.text, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ),
              for (final (n, f) in _items.indexed) _itemCard(n, f, issues),
              OutlinedButton.icon(
                key: const ValueKey('sa-add-item'),
                onPressed: _items.length >= maxZatcaItems
                    ? null
                    : () => setState(() {
                        _items.add(_Item());
                        _made = null;
                      }),
                icon: const Icon(AppIcons.add, size: 18),
                label: const Text('Add an item'),
              ),
              const SizedBox(height: AppSpacing.md),
              _summary(draft),
            ],
          ),
          TaxSection(
            title: 'Notes',
            children: [TaxField(controller: _notes, label: 'Notes (optional)', onChanged: _changed, maxLines: 3)],
          ),
          FilledButton.icon(
            key: const ValueKey('sa-create'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : _create,
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.pdf, size: 20),
            label: Text(standard ? 'Create tax invoice' : 'Create simplified invoice'),
          ),
          if (_made != null) ...[
            const SizedBox(height: AppSpacing.md),
            PdfResultCard(title: p.basename(_made!), message: tr('Saved on this phone. Share it, or save it to Files.'), path: _made!),
          ],
        ],
      ),
    );
  }
}
