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
import '../data/gst_pdf.dart';
import '../data/tax_profile_store.dart';
import '../domain/gst.dart';
import '../domain/tax_common.dart';
import 'form_kit.dart';

Future<Uint8List> _loadAsset(String path) async => (await rootBundle.load(path)).buffer.asUint8List();

class _Item {
  final description = TextEditingController();
  final hsn = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final unit = TextEditingController();
  final price = TextEditingController();
  final rate = TextEditingController(text: '18');

  void dispose() {
    for (final c in [description, hsn, quantity, unit, price, rate]) {
      c.dispose();
    }
  }
}

/// Makes a GST tax invoice or bill of supply as a PDF, with CGST and SGST inside a state and IGST between states, an HSN summary,
/// the amount in words and a UPI code. Everything is worked out on this phone.
class GstInvoicePage extends StatefulWidget {
  const GstInvoicePage({
    super.key,
    this.workDir = getTemporaryDirectory,
    this.loadAsset = _loadAsset,
    this.store = const TaxProfileStore(gstProfileKey),
    this.now,
  });
  final Future<Directory> Function() workDir;
  final Future<Uint8List> Function(String asset) loadAsset;
  final TaxProfileStore store;
  final DateTime? now;

  @override
  State<GstInvoicePage> createState() => _GstInvoicePageState();
}

class _GstInvoicePageState extends State<GstInvoicePage> {
  final _sName = TextEditingController();
  final _sAddress = TextEditingController();
  final _sCity = TextEditingController();
  final _sPin = TextEditingController();
  final _sGstin = TextEditingController();
  final _sPhone = TextEditingController();
  final _sEmail = TextEditingController();
  final _bName = TextEditingController();
  final _bAddress = TextEditingController();
  final _bCity = TextEditingController();
  final _bPin = TextEditingController();
  final _bGstin = TextEditingController();
  final _number = TextEditingController();
  final _notes = TextEditingController();
  final _bank = TextEditingController();
  final _account = TextEditingController();
  final _ifsc = TextEditingController();
  final _upi = TextEditingController();
  final _items = <_Item>[_Item()];
  GstDocument _doc = GstDocument.taxInvoice;
  String _sState = '';
  String _bState = '';
  String _pos = '';
  bool _reverse = false;
  bool _submitted = false;
  bool _busy = false;
  String? _made;
  late DateTime _date = widget.now ?? DateTime.now();

  List<TextEditingController> get _all => [
    _sName,
    _sAddress,
    _sCity,
    _sPin,
    _sGstin,
    _sPhone,
    _sEmail,
    _bName,
    _bAddress,
    _bCity,
    _bPin,
    _bGstin,
    _number,
    _notes,
    _bank,
    _account,
    _ifsc,
    _upi,
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
      _sAddress.text = v['address'] ?? '';
      _sCity.text = v['city'] ?? '';
      _sPin.text = v['pin'] ?? '';
      _sGstin.text = v['gstin'] ?? '';
      _sPhone.text = v['phone'] ?? '';
      _sEmail.text = v['email'] ?? '';
      _sState = v['state'] ?? '';
      _bank.text = v['bank'] ?? '';
      _account.text = v['account'] ?? '';
      _ifsc.text = v['ifsc'] ?? '';
      _upi.text = v['upi'] ?? '';
      _number.text = nextGstInvoiceNumber(v['lastNumber'] ?? '', _date);
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

  String get _placeOfSupply => _pos.isNotEmpty ? _pos : _bState;

  GstDraft get _draft => GstDraft(
    document: _doc,
    seller: GstParty(
      name: _sName.text,
      address: _sAddress.text,
      city: _sCity.text,
      pin: _sPin.text,
      stateCode: _sState,
      gstin: _sGstin.text,
      phone: _sPhone.text,
      email: _sEmail.text,
    ),
    buyer: GstParty(name: _bName.text, address: _bAddress.text, city: _bCity.text, pin: _bPin.text, stateCode: _bState, gstin: _bGstin.text),
    number: _number.text,
    date: _date,
    placeOfSupply: _placeOfSupply,
    reverseCharge: _reverse,
    items: [
      for (final i in _items)
        GstLine(
          description: i.description.text,
          hsn: i.hsn.text,
          quantity: parseQuantity(i.quantity.text) ?? 0,
          unit: i.unit.text,
          unitPriceCents: parseCents(i.price.text) ?? 0,
          rateHundredths: _doc == GstDocument.taxInvoice ? (rateHundredths(i.rate.text) ?? 0) : 0,
        ),
    ],
    notes: _notes.text,
    bankName: _bank.text,
    accountNumber: _account.text,
    ifsc: _ifsc.text,
    upiId: _upi.text,
  );

  List<TaxIssue> get _issueList {
    final out = <TaxIssue>[];
    for (final (n, i) in _items.indexed) {
      if (parseQuantity(i.quantity.text) == null) out.add(TaxIssue('item.$n.quantity', 'Item {n}: the quantity must be a number above zero.', {'n': n + 1}));
      if (parseCents(i.price.text) == null) out.add(TaxIssue('item.$n.price', 'Item {n}: the price must be an amount, for example 125.50.', {'n': n + 1}));
      if (_doc == GstDocument.taxInvoice && rateHundredths(i.rate.text) == null)
        out.add(TaxIssue('item.$n.rate', 'Item {n}: the GST rate must be a number such as 18 or 2.5, or 0.', {'n': n + 1}));
    }
    return [...out, ...gstIssues(_draft)];
  }

  void _changed() => setState(() => _made = null);

  void _sellerGstinChanged() {
    final g = _sGstin.text.trim().toUpperCase();
    if (g.length == 15 && gstinIssue('x', g) == null) _sState = g.substring(0, 2);
    _changed();
  }

  void _buyerGstinChanged() {
    final g = _bGstin.text.trim().toUpperCase();
    if (g.length == 15 && gstinIssue('x', g) == null) _bState = g.substring(0, 2);
    _changed();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2017, 7, 1), lastDate: DateTime(2100));
    if (d != null && mounted) {
      setState(() {
        _date = d;
        _made = null;
      });
    }
  }

  Future<void> _create() async {
    setState(() => _submitted = true);
    final issues = _issueList;
    if (issues.isNotEmpty) {
      showMessage(context, 'Fix the marked fields, then try again.');
      return;
    }
    setState(() => _busy = true);
    try {
      final d = _draft;
      final bytes = await buildGstPdf(d, loadAsset: widget.loadAsset);
      final dir = await Directory(p.join((await widget.workDir()).path, 'invoices')).create(recursive: true);
      final safe = d.number.trim().replaceAll(RegExp(r'[^\w\-]+'), '_');
      final file = await File(p.join(dir.path, 'GST_$safe.pdf')).writeAsBytes(bytes, flush: true);
      await widget.store.save({
        'name': _sName.text.trim(),
        'address': _sAddress.text.trim(),
        'city': _sCity.text.trim(),
        'pin': _sPin.text.trim(),
        'gstin': _sGstin.text.trim().toUpperCase(),
        'phone': _sPhone.text.trim(),
        'email': _sEmail.text.trim(),
        'state': _sState,
        'bank': _bank.text.trim(),
        'account': _account.text.trim(),
        'ifsc': _ifsc.text.trim().toUpperCase(),
        'upi': _upi.text.trim(),
        'lastNumber': d.number.trim(),
      });
      if (mounted) setState(() => _made = file.path);
    } on Object {
      if (mounted) showMessage(context, 'The invoice could not be made. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _statePicker(String label, String value, ValueChanged<String> onPick, {TaxIssue? issue, Key? fieldKey}) => KeyedSubtree(
    key: ValueKey('state-$label-$value'),
    child: DropdownButtonFormField<String>(
      key: fieldKey,
      isExpanded: true,
      initialValue: value.isEmpty ? null : value,
      decoration: InputDecoration(labelText: tr(label), errorText: issue?.text, errorMaxLines: 3),
      items: [
        for (final s in gstStates)
          DropdownMenuItem(
            value: s.code,
            child: Text.rich(TextSpan(text: '${s.name} (${s.code})'), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) {
          onPick(v);
          _changed();
        }
      },
    ),
  );

  Widget _itemCard(int n, _Item f, Map<String, TaxIssue> issues) {
    final tax = _doc == GstDocument.taxInvoice;
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
                  key: ValueKey('gst-remove-$n'),
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
                child: TaxField(
                  controller: f.hsn,
                  label: 'HSN or SAC code',
                  onChanged: _changed,
                  issue: at('hsn'),
                  keyboard: TextInputType.number,
                  caps: TextCapitalization.none,
                  maxLength: 8,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TaxField(controller: f.unit, label: 'Unit (Nos, Kg)', onChanged: _changed, caps: TextCapitalization.none),
              ),
            ],
          ),
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
                  label: 'Price each, before tax *',
                  onChanged: _changed,
                  issue: at('price'),
                  keyboard: decimalKeyboard,
                  prefix: '\u20B9 ',
                ),
              ),
            ],
          ),
          if (tax) ...[
            taxGap,
            TaxField(controller: f.rate, label: 'GST rate % *', onChanged: _changed, issue: at('rate'), keyboard: decimalKeyboard),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in gstRateChips)
                  ChoiceChip(
                    key: ValueKey('gst-rate-$n-$r'),
                    label: Text('$r%'),
                    selected: rateHundredths(f.rate.text) == (r * 100).round(),
                    onSelected: (_) {
                      f.rate.text = '$r';
                      _changed();
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _summary(GstDraft d) {
    final t = computeGst(d);
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
      key: const ValueKey('gst-summary'),
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppSpacing.radius)),
      child: Column(
        children: [
          row(tr('Taxable value'), '\u20B9 ${groupIndian(t.taxable)}'),
          if (d.isTax && !d.interState) ...[
            row('CGST', '\u20B9 ${groupIndian(t.cgst)}'),
            row(d.sellerIsUt ? 'UTGST' : 'SGST', '\u20B9 ${groupIndian(t.sgst)}'),
          ],
          if (d.isTax && d.interState) row('IGST', '\u20B9 ${groupIndian(t.igst)}'),
          if (t.roundOff != 0) row(tr('Round off'), '${t.roundOff < 0 ? '-' : ''}\u20B9 ${groupIndian(t.roundOff.abs())}'),
          const Divider(),
          row(tr('Total'), '\u20B9 ${groupIndian(t.grand)}', strong: true),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final issues = issuesByField(_issueList);
    TaxIssue? at(String k) => _submitted ? issues[k] : null;
    final tax = _doc == GstDocument.taxInvoice;
    final place = _placeOfSupply;
    return Scaffold(
      appBar: AppBar(title: const Text('GST invoice')),
      body: ListView(
        padding: contentPadding(context).copyWith(bottom: AppSpacing.xl),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const Text(
            'Make a GST tax invoice or bill of supply as a PDF. The tax is worked out on this phone. It is not an e-invoice with an IRN, which sellers above the e-invoicing limit make on the government portal.',
            style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<GstDocument>(
            key: const ValueKey('gst-document'),
            segments: const [
              ButtonSegment(value: GstDocument.taxInvoice, label: Text('Tax invoice')),
              ButtonSegment(value: GstDocument.billOfSupply, label: Text('Bill of supply')),
            ],
            selected: {_doc},
            onSelectionChanged: (s) => setState(() {
              _doc = s.first;
              _made = null;
            }),
          ),
          const SizedBox(height: 6),
          Text(
            tax ? 'For registered sellers who charge GST.' : 'For composition dealers and exempt supplies. It shows no tax.',
            style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          TaxSection(
            title: 'Your business',
            children: [
              TaxField(controller: _sName, label: 'Business name *', onChanged: _changed, issue: at('seller.name'), caps: TextCapitalization.words),
              taxGap,
              TaxField(controller: _sAddress, label: 'Address *', onChanged: _changed, issue: at('seller.address'), maxLines: 2),
              taxGap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TaxField(controller: _sCity, label: 'Town or city', onChanged: _changed, caps: TextCapitalization.words),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TaxField(
                      controller: _sPin,
                      label: 'PIN code',
                      onChanged: _changed,
                      issue: at('seller.pin'),
                      keyboard: TextInputType.number,
                      caps: TextCapitalization.none,
                      maxLength: 6,
                    ),
                  ),
                ],
              ),
              taxGap,
              _statePicker('Your state *', _sState, (v) => _sState = v, issue: at('seller.state'), fieldKey: const ValueKey('gst-seller-state')),
              taxGap,
              TaxField(
                controller: _sGstin,
                label: tax ? 'Your GSTIN *' : 'Your GSTIN (if you have one)',
                onChanged: _sellerGstinChanged,
                issue: at('seller.gstin'),
                helper: '15 characters, for example 27AAPFU0939F1ZV. The state is filled in from it.',
                caps: TextCapitalization.characters,
                maxLength: 15,
              ),
              taxGap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TaxField(
                      controller: _sPhone,
                      label: 'Phone (optional)',
                      onChanged: _changed,
                      keyboard: TextInputType.phone,
                      caps: TextCapitalization.none,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TaxField(
                      controller: _sEmail,
                      label: 'Email (optional)',
                      onChanged: _changed,
                      issue: at('seller.email'),
                      keyboard: TextInputType.emailAddress,
                      caps: TextCapitalization.none,
                    ),
                  ),
                ],
              ),
            ],
          ),
          TaxSection(
            title: 'Customer',
            children: [
              TaxField(controller: _bName, label: 'Customer name *', onChanged: _changed, issue: at('buyer.name'), caps: TextCapitalization.words),
              taxGap,
              TaxField(controller: _bAddress, label: 'Address (optional)', onChanged: _changed, maxLines: 2),
              taxGap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TaxField(controller: _bCity, label: 'Town or city', onChanged: _changed, caps: TextCapitalization.words),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TaxField(
                      controller: _bPin,
                      label: 'PIN code',
                      onChanged: _changed,
                      issue: at('buyer.pin'),
                      keyboard: TextInputType.number,
                      caps: TextCapitalization.none,
                      maxLength: 6,
                    ),
                  ),
                ],
              ),
              taxGap,
              _statePicker('Customer\'s state *', _bState, (v) => _bState = v, fieldKey: const ValueKey('gst-buyer-state')),
              taxGap,
              TaxField(
                controller: _bGstin,
                label: 'Customer GSTIN (optional)',
                onChanged: _buyerGstinChanged,
                issue: at('buyer.gstin'),
                helper: 'A business customer needs it to claim input tax credit.',
                caps: TextCapitalization.characters,
                maxLength: 15,
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
                helper: 'Up to 16 letters, digits, / or -. It must not repeat in the financial year.',
                caps: TextCapitalization.characters,
                maxLength: 16,
              ),
              taxGap,
              OutlinedButton.icon(
                key: const ValueKey('gst-date'),
                onPressed: _pickDate,
                icon: const Icon(AppIcons.timer, size: 18),
                label: Text('${tr('Invoice date')}: ${formatDate(_date)}'),
              ),
              taxGap,
              _statePicker('Place of supply *', place, (v) => _pos = v, issue: at('place'), fieldKey: const ValueKey('gst-place')),
              const SizedBox(height: 6),
              Text(
                place.isEmpty
                    ? 'The place of supply is the state the goods or services go to. It decides which tax is charged.'
                    : (draft.interState ? 'Between states: IGST is charged.' : 'Inside the state: CGST and SGST are charged.'),
                key: const ValueKey('gst-which-tax'),
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
              ),
              if (tax)
                SwitchListTile(
                  key: const ValueKey('gst-reverse'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reverse charge'),
                  subtitle: const Text('The customer pays the tax, not you'),
                  value: _reverse,
                  onChanged: (v) => setState(() {
                    _reverse = v;
                    _made = null;
                  }),
                ),
            ],
          ),
          TaxSection(
            title: 'Items',
            hint: tax ? 'Rates are set by the GST Council and change. Check the current rate of what you sell.' : null,
            children: [
              if (at('items') != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(at('items')!.text, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ),
              for (final (n, f) in _items.indexed) _itemCard(n, f, issues),
              OutlinedButton.icon(
                key: const ValueKey('gst-add-item'),
                onPressed: _items.length >= maxGstItems
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
            title: 'Payment details (optional)',
            hint: 'Shown on the invoice. A UPI ID adds a code the customer can scan to pay the exact amount.',
            children: [
              TaxField(controller: _bank, label: 'Bank name', onChanged: _changed, caps: TextCapitalization.words),
              taxGap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TaxField(
                      controller: _account,
                      label: 'Account number',
                      onChanged: _changed,
                      issue: at('account'),
                      keyboard: TextInputType.number,
                      caps: TextCapitalization.none,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: TaxField(
                      controller: _ifsc,
                      label: 'IFSC',
                      onChanged: _changed,
                      issue: at('ifsc'),
                      caps: TextCapitalization.characters,
                      maxLength: 11,
                    ),
                  ),
                ],
              ),
              taxGap,
              TaxField(
                controller: _upi,
                label: 'UPI ID',
                onChanged: _changed,
                issue: at('upi'),
                caps: TextCapitalization.none,
                keyboard: TextInputType.emailAddress,
              ),
              taxGap,
              TaxField(controller: _notes, label: 'Notes and terms (optional)', onChanged: _changed, maxLines: 3),
            ],
          ),
          FilledButton.icon(
            key: const ValueKey('gst-create'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : _create,
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.pdf, size: 20),
            label: Text(tax ? 'Create tax invoice' : 'Create bill of supply'),
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
