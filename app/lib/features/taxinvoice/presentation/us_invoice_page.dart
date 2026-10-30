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
import '../data/us_invoice_pdf.dart';
import '../domain/tax_common.dart';
import '../domain/us_invoice.dart';
import 'form_kit.dart';

Future<Uint8List> _loadAsset(String path) async => (await rootBundle.load(path)).buffer.asUint8List();

class _Item {
  final description = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final price = TextEditingController();
  bool taxable = true;

  void dispose() {
    for (final c in [description, quantity, price]) {
      c.dispose();
    }
  }
}

/// Makes a US invoice as a PDF: line items that are taxed or not, a discount, shipping, sales tax at one combined rate, an exempt
/// customer, a payment already received, and the balance due. The state rates offered are references, not tax advice.
class UsInvoicePage extends StatefulWidget {
  const UsInvoicePage({
    super.key,
    this.workDir = getTemporaryDirectory,
    this.loadAsset = _loadAsset,
    this.store = const TaxProfileStore(usInvoiceProfileKey),
    this.now,
  });
  final Future<Directory> Function() workDir;
  final Future<Uint8List> Function(String asset) loadAsset;
  final TaxProfileStore store;
  final DateTime? now;

  @override
  State<UsInvoicePage> createState() => _UsInvoicePageState();
}

class _UsInvoicePageState extends State<UsInvoicePage> {
  final _sName = TextEditingController();
  final _sAddress = TextEditingController();
  final _sCity = TextEditingController();
  final _sZip = TextEditingController();
  final _sPhone = TextEditingController();
  final _sEmail = TextEditingController();
  final _sTaxId = TextEditingController();
  final _bName = TextEditingController();
  final _bAddress = TextEditingController();
  final _bCity = TextEditingController();
  final _bZip = TextEditingController();
  final _bEmail = TextEditingController();
  final _bCert = TextEditingController();
  final _number = TextEditingController();
  final _discount = TextEditingController();
  final _shipping = TextEditingController();
  final _rate = TextEditingController();
  final _paid = TextEditingController();
  final _payment = TextEditingController();
  final _notes = TextEditingController();
  final _items = <_Item>[_Item()];
  String _sState = '';
  String _bState = '';
  int _terms = 30;
  bool _discountPercent = true;
  bool _shippingTaxable = false;
  bool _exempt = false;
  bool _submitted = false;
  bool _busy = false;
  String? _made;
  late DateTime _date = widget.now ?? DateTime.now();

  List<TextEditingController> get _all => [
    _sName,
    _sAddress,
    _sCity,
    _sZip,
    _sPhone,
    _sEmail,
    _sTaxId,
    _bName,
    _bAddress,
    _bCity,
    _bZip,
    _bEmail,
    _bCert,
    _number,
    _discount,
    _shipping,
    _rate,
    _paid,
    _payment,
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
      _sAddress.text = v['address'] ?? '';
      _sCity.text = v['city'] ?? '';
      _sZip.text = v['zip'] ?? '';
      _sPhone.text = v['phone'] ?? '';
      _sEmail.text = v['email'] ?? '';
      _sTaxId.text = v['taxId'] ?? '';
      _sState = v['state'] ?? '';
      _payment.text = v['payment'] ?? '';
      _terms = int.tryParse(v['terms'] ?? '') ?? 30;
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

  /// An amount in cents; empty is nothing, and null is text that is not an amount.
  int? _cents(String text) => text.trim().isEmpty ? 0 : parseCents(text);

  UsDraft get _draft => UsDraft(
    seller: UsParty(
      name: _sName.text,
      address: _sAddress.text,
      city: _sCity.text,
      state: _sState,
      zip: _sZip.text,
      phone: _sPhone.text,
      email: _sEmail.text,
      taxId: _sTaxId.text,
    ),
    buyer: UsParty(name: _bName.text, address: _bAddress.text, city: _bCity.text, state: _bState, zip: _bZip.text, email: _bEmail.text, taxId: _bCert.text),
    number: _number.text,
    date: _date,
    termsDays: _terms,
    items: [
      for (final i in _items)
        UsLine(
          description: i.description.text,
          quantity: parseQuantity(i.quantity.text) ?? 0,
          unitPriceCents: parseCents(i.price.text) ?? 0,
          taxable: i.taxable,
        ),
    ],
    discountIsPercent: _discountPercent,
    discountValue: _discountPercent ? (_discount.text.trim().isEmpty ? 0 : (rateHundredths(_discount.text) ?? 0)) : (_cents(_discount.text) ?? 0),
    shippingCents: _cents(_shipping.text) ?? 0,
    shippingTaxable: _shippingTaxable,
    taxRate: _rate.text.trim().isEmpty ? 0 : (parseUsRate(_rate.text) ?? 0),
    exempt: _exempt,
    paidCents: _cents(_paid.text) ?? 0,
    payment: _payment.text,
    notes: _notes.text,
  );

  List<TaxIssue> get _issueList {
    final out = <TaxIssue>[];
    for (final (n, i) in _items.indexed) {
      if (parseQuantity(i.quantity.text) == null) out.add(TaxIssue('item.$n.quantity', 'Item {n}: the quantity must be a number above zero.', {'n': n + 1}));
      if (parseCents(i.price.text) == null) out.add(TaxIssue('item.$n.price', 'Item {n}: the price must be an amount, for example 125.50.', {'n': n + 1}));
    }
    if (_discount.text.trim().isNotEmpty && (_discountPercent ? rateHundredths(_discount.text) == null : _cents(_discount.text) == null)) {
      out.add(TaxIssue('discount', _discountPercent ? 'The discount must be a percent such as 10 or 7.5.' : 'The discount must be an amount such as 25.00.'));
    }
    if (_cents(_shipping.text) == null) out.add(const TaxIssue('shipping', 'The shipping must be an amount such as 9.95.'));
    if (_cents(_paid.text) == null) out.add(const TaxIssue('paid', 'The amount paid must be an amount such as 100.00.'));
    if (_rate.text.trim().isNotEmpty && parseUsRate(_rate.text) == null)
      out.add(const TaxIssue('rate', 'The tax rate must be a percent from 0 to 20, such as 8.25.'));
    return [...out, ...usIssues(_draft)];
  }

  void _changed() => setState(() => _made = null);

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null && mounted) {
      setState(() {
        _date = d;
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
      final bytes = await buildUsInvoicePdf(d, loadAsset: widget.loadAsset);
      final dir = await Directory(p.join((await widget.workDir()).path, 'invoices')).create(recursive: true);
      final safe = d.number.trim().replaceAll(RegExp(r'[^\w\-]+'), '_');
      final file = await File(p.join(dir.path, 'Invoice_$safe.pdf')).writeAsBytes(bytes, flush: true);
      await widget.store.save({
        'name': _sName.text.trim(),
        'address': _sAddress.text.trim(),
        'city': _sCity.text.trim(),
        'zip': _sZip.text.trim(),
        'state': _sState,
        'phone': _sPhone.text.trim(),
        'email': _sEmail.text.trim(),
        'taxId': _sTaxId.text.trim(),
        'payment': _payment.text.trim(),
        'terms': '$_terms',
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
        for (final s in usStates)
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
                  key: ValueKey('us-remove-$n'),
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
                child: TaxField(controller: f.price, label: 'Price each *', onChanged: _changed, issue: at('price'), keyboard: decimalKeyboard, prefix: '\$ '),
              ),
            ],
          ),
          SwitchListTile(
            key: ValueKey('us-taxable-$n'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Charge sales tax on this item'),
            value: f.taxable,
            onChanged: (v) => setState(() {
              f.taxable = v;
              _made = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _summary(UsDraft d) {
    final t = computeUs(d);
    String money(int c) => '${c < 0 ? '-' : ''}\$${groupWestern(c.abs())}';
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
      key: const ValueKey('us-summary'),
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppSpacing.radius)),
      child: Column(
        children: [
          row(tr('Subtotal'), money(t.subtotal)),
          if (t.discount > 0) row(tr('Discount'), money(-t.discount)),
          if (t.shipping > 0) row(tr('Shipping'), money(t.shipping)),
          if (d.taxRate > 0 || d.exempt) row(d.exempt ? tr('Sales tax (exempt)') : trf('Sales tax ({rate}%)', {'rate': usRateText(d.taxRate)}), money(t.tax)),
          const Divider(),
          row(tr('Total'), money(t.total), strong: true),
          if (t.paid > 0) ...[row(tr('Amount paid'), money(-t.paid)), row(tr('Balance due'), money(t.balance), strong: true)],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final issues = issuesByField(_issueList);
    TaxIssue? at(String k) => _submitted ? issues[k] : null;
    final rateState = usStateOf(_bState) ?? usStateOf(_sState);
    return Scaffold(
      appBar: AppBar(title: const Text('US invoice')),
      body: ListView(
        padding: contentPadding(context).copyWith(bottom: AppSpacing.xl),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const Text(
            'Make an invoice in US dollars as a PDF, with sales tax at one rate you choose. It is made on this phone.',
            style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          TaxSection(
            title: 'Your business',
            children: [
              TaxField(controller: _sName, label: 'Business name *', onChanged: _changed, issue: at('seller.name'), caps: TextCapitalization.words),
              taxGap,
              TaxField(controller: _sAddress, label: 'Street address *', onChanged: _changed, issue: at('seller.address')),
              taxGap,
              TaxField(controller: _sCity, label: 'City *', onChanged: _changed, issue: at('seller.city'), caps: TextCapitalization.words),
              taxGap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _statePicker('State *', _sState, (v) => _sState = v, issue: at('seller.state'), fieldKey: const ValueKey('us-seller-state')),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: TaxField(
                      controller: _sZip,
                      label: 'ZIP code *',
                      onChanged: _changed,
                      issue: at('seller.zip'),
                      keyboard: TextInputType.number,
                      caps: TextCapitalization.none,
                      maxLength: 10,
                    ),
                  ),
                ],
              ),
              taxGap,
              TaxField(
                controller: _sTaxId,
                label: 'EIN or sales tax permit no. (optional)',
                onChanged: _changed,
                issue: at('seller.taxId'),
                helper: 'An EIN looks like 12-3456789.',
                caps: TextCapitalization.characters,
                maxLength: 20,
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
            title: 'Bill to',
            children: [
              TaxField(controller: _bName, label: 'Customer name *', onChanged: _changed, issue: at('buyer.name'), caps: TextCapitalization.words),
              taxGap,
              TaxField(controller: _bAddress, label: 'Street address (optional)', onChanged: _changed),
              taxGap,
              TaxField(controller: _bCity, label: 'City', onChanged: _changed, caps: TextCapitalization.words),
              taxGap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _statePicker('State', _bState, (v) => _bState = v, fieldKey: const ValueKey('us-buyer-state'))),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: TaxField(
                      controller: _bZip,
                      label: 'ZIP code',
                      onChanged: _changed,
                      issue: at('buyer.zip'),
                      keyboard: TextInputType.number,
                      caps: TextCapitalization.none,
                      maxLength: 10,
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
              OutlinedButton.icon(
                key: const ValueKey('us-date'),
                onPressed: _pickDate,
                icon: const Icon(AppIcons.timer, size: 18),
                label: Text('${tr('Invoice date')}: ${formatDate(_date)}'),
              ),
              taxGap,
              Text(tr('Payment terms'), style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final days in usTermsDays)
                    ChoiceChip(
                      key: ValueKey('us-terms-$days'),
                      label: Text(usTermsText(days)),
                      selected: _terms == days,
                      onSelected: (_) => setState(() {
                        _terms = days;
                        _made = null;
                      }),
                    ),
                ],
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
                key: const ValueKey('us-add-item'),
                onPressed: _items.length >= maxUsItems
                    ? null
                    : () => setState(() {
                        _items.add(_Item());
                        _made = null;
                      }),
                icon: const Icon(AppIcons.add, size: 18),
                label: const Text('Add an item'),
              ),
            ],
          ),
          TaxSection(
            title: 'Discount, shipping and tax',
            children: [
              SegmentedButton<bool>(
                key: const ValueKey('us-discount-mode'),
                segments: const [
                  ButtonSegment(value: true, label: Text('Discount %')),
                  ButtonSegment(value: false, label: Text('Discount \$')),
                ],
                selected: {_discountPercent},
                onSelectionChanged: (s) => setState(() {
                  _discountPercent = s.first;
                  _discount.clear();
                  _made = null;
                }),
              ),
              taxGap,
              TaxField(
                controller: _discount,
                label: _discountPercent ? 'Discount (percent, optional)' : 'Discount (amount, optional)',
                onChanged: _changed,
                issue: at('discount'),
                keyboard: decimalKeyboard,
              ),
              taxGap,
              TaxField(
                controller: _shipping,
                label: 'Shipping (optional)',
                onChanged: _changed,
                issue: at('shipping'),
                keyboard: decimalKeyboard,
                prefix: '\$ ',
              ),
              SwitchListTile(
                key: const ValueKey('us-shipping-taxable'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Charge sales tax on shipping'),
                subtitle: const Text('Some states tax shipping, others do not'),
                value: _shippingTaxable,
                onChanged: (v) => setState(() {
                  _shippingTaxable = v;
                  _made = null;
                }),
              ),
              const Divider(),
              SwitchListTile(
                key: const ValueKey('us-exempt'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Customer is tax exempt'),
                subtitle: const Text('For a resale or exemption certificate'),
                value: _exempt,
                onChanged: (v) => setState(() {
                  _exempt = v;
                  _made = null;
                }),
              ),
              if (_exempt) ...[
                taxGap,
                TaxField(
                  controller: _bCert,
                  label: 'Exemption certificate no. (optional)',
                  onChanged: _changed,
                  caps: TextCapitalization.characters,
                  maxLength: 20,
                ),
              ] else ...[
                taxGap,
                TaxField(
                  controller: _rate,
                  label: 'Sales tax rate (%)',
                  onChanged: _changed,
                  issue: at('rate'),
                  helper: 'The state and local rates added together, for example 8.25. Leave empty for no tax.',
                  keyboard: decimalKeyboard,
                ),
                if (rateState != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          trf('{state} state rate: {rate}% ({when}). Cities and counties add their own tax.', {
                            'state': rateState.name,
                            'rate': usRateText(rateState.baseRate),
                            'when': usRatesAsOf,
                          }),
                          key: const ValueKey('us-state-rate'),
                          style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('us-use-state-rate'),
                        onPressed: () {
                          _rate.text = usRateText(rateState.baseRate);
                          _changed();
                        },
                        child: const Text('Use it'),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: AppSpacing.md),
              _summary(draft),
            ],
          ),
          TaxSection(
            title: 'Payment',
            hint: 'Optional. A deposit already received comes off the balance due.',
            children: [
              TaxField(controller: _paid, label: 'Amount already paid', onChanged: _changed, issue: at('paid'), keyboard: decimalKeyboard, prefix: '\$ '),
              taxGap,
              TaxField(
                controller: _payment,
                label: 'Payment instructions',
                onChanged: _changed,
                maxLines: 3,
                helper: 'For example: pay by ACH, Zelle, or check made out to your business.',
              ),
              taxGap,
              TaxField(controller: _notes, label: 'Notes (optional)', onChanged: _changed, maxLines: 3),
            ],
          ),
          FilledButton.icon(
            key: const ValueKey('us-create'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : _create,
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.pdf, size: 20),
            label: const Text('Create invoice'),
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
