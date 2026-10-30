import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../documents/presentation/widgets/document_widgets.dart' show confirmDestructive;
import '../../export/domain/repositories/export_repository.dart';
import '../../invoice/domain/invoice.dart' show formatMoney, parseCents;
import '../data/vat_refund_store.dart';
import '../domain/vat_refund.dart';

Future<String?> _pickPhoto(bool camera) async => (await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery))?.path;

enum _Filter { all, todo, onTheWay, done }

String _money(int cents, String currency, String country) => formatMoney(cents, currency, country: country.isEmpty ? 'DE' : country);

/// Keeps the receipts of tax-free shopping, with the day each must be stamped by, so the VAT is not lost. Everything stays on the phone.
class VatRefundPage extends StatefulWidget {
  const VatRefundPage({super.key, this.store, this.pickPhoto = _pickPhoto, this.now, this.workDir = getTemporaryDirectory});
  final VatRefundStore? store;
  final Future<String?> Function(bool camera) pickPhoto;
  final DateTime Function()? now;
  final Future<Directory> Function() workDir;

  @override
  State<VatRefundPage> createState() => _VatRefundPageState();
}

class _VatRefundPageState extends State<VatRefundPage> {
  late final VatRefundStore _store = widget.store ?? VatRefundStore();
  List<VatReceipt> _receipts = const [];
  bool _loaded = false;
  _Filter _filter = _Filter.all;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _store.load();
    if (mounted) {
      setState(() {
        _receipts = list;
        _loaded = true;
      });
    }
  }

  Future<void> _persist(List<VatReceipt> next) async {
    setState(() => _receipts = next);
    await _store.save(next);
  }

  Future<void> _edit(VatReceipt? existing) async {
    final result = await Navigator.of(context).push<_EditResult>(
      MaterialPageRoute(
        builder: (_) => _ReceiptEditor(store: _store, existing: existing, pickPhoto: widget.pickPhoto, today: _now),
      ),
    );
    if (result == null || !mounted) return;
    if (result.delete) {
      await _store.deletePhoto(existing?.photoPath);
      await _persist([
        for (final r in _receipts)
          if (r.id != existing?.id) r,
      ]);
      return;
    }
    final saved = result.receipt!;
    final others = [
      for (final r in _receipts)
        if (r.id != saved.id) r,
    ];
    await _persist([...others, saved]);
  }

  Future<void> _advance(VatReceipt r) async {
    final next = RefundStatus.values[(r.status.index + 1).clamp(0, RefundStatus.values.length - 1)];
    await _persist([for (final x in _receipts) x.id == r.id ? x.copyWith(status: next) : x]);
  }

  Future<void> _shareCsv() async {
    final dir = await widget.workDir();
    final file = await File(p.join(dir.path, 'vat_refund_receipts.csv')).writeAsString(receiptsCsv(_receipts), flush: true);
    final r = await sl<ShareService>().shareFile(path: file.path, mimeType: 'text/csv', subject: 'VAT refund receipts');
    if (mounted && r.failureOrNull != null) showFailure(context, r.failureOrNull!);
  }

  Future<void> _showPhoto(VatReceipt r) => showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: InteractiveViewer(
        child: Image.file(
          File(r.photoPath!),
          errorBuilder: (_, _, _) => const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Text('The picture is no longer there.')),
        ),
      ),
    ),
  );

  bool _matches(VatReceipt r) => switch (_filter) {
    _Filter.all => true,
    _Filter.todo => r.status == RefundStatus.toStamp,
    _Filter.onTheWay => r.status == RefundStatus.stamped || r.status == RefundStatus.sent,
    _Filter.done => r.status == RefundStatus.refunded,
  };

  Widget _deadline(VatReceipt r) {
    if (r.status != RefundStatus.toStamp) return const SizedBox.shrink();
    final left = daysLeft(r.date, _now);
    final (text, color) = left < 0
        ? (tr('Deadline passed'), AppColors.danger)
        : (left == 0
              ? (tr('Last day to stamp'), AppColors.danger)
              : (trf('{n} days left to stamp', {'n': left}), left <= 14 ? AppColors.warning : AppColors.inkMuted));
    return Text(
      text,
      key: ValueKey('deadline-${r.id}'),
      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final r in _receipts)
        if (_matches(r)) r,
    ]..sort((a, b) => a.date.compareTo(b.date));
    final totals = summarize(_receipts, _now);
    return Scaffold(
      appBar: AppBar(
        title: const Text('VAT refund receipts'),
        actions: [if (_receipts.isNotEmpty) IconButton(tooltip: tr('Share the list as a spreadsheet'), icon: const Icon(AppIcons.share), onPressed: _shareCsv)],
      ),
      body: ListView(
        padding: contentPadding(context),
        children: [
          const Text(
            'Shopping tax-free in Europe? Keep each receipt and tax-free form here with its deadline. Get the form stamped by customs when you leave, and tick it off as it moves on.',
            style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            key: const ValueKey('add-receipt'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add a receipt'),
          ),
          if (totals.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final t in totals)
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trf('VAT in {currency}', {'currency': t.currency}), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      _sum(tr('Waiting for the stamp'), t.waitingCents, t.currency, AppColors.warning),
                      _sum(tr('Stamped, refund on its way'), t.stampedCents, t.currency, AppColors.primary),
                      _sum(tr('Refunded'), t.refundedCents, t.currency, AppColors.success),
                      if (t.lostCents > 0) _sum(tr('Deadline passed'), t.lostCents, t.currency, AppColors.danger),
                    ],
                  ),
                ),
              ),
          ],
          if (_receipts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final (f, label) in [(_Filter.all, 'All'), (_Filter.todo, 'Needs stamp'), (_Filter.onTheWay, 'On its way'), (_Filter.done, 'Refunded')])
                  ChoiceChip(label: Text(label), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_loaded && _receipts.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'No receipts yet. Add one right after you shop, with a picture of the receipt and the tax-free form.',
                  style: TextStyle(height: 1.4),
                ),
              ),
            ),
          for (final r in shown)
            Card(
              key: ValueKey('receipt-${r.id}'),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSpacing.radius),
                onTap: () => _edit(r),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.store.isEmpty ? tr('Receipt') : r.store,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (r.photoPath != null)
                            IconButton(
                              tooltip: tr('Show the picture'),
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(AppIcons.gallery, size: 20),
                              onPressed: () => _showPhoto(r),
                            ),
                        ],
                      ),
                      Text(
                        '${formatDate(r.date)}${r.country.isEmpty ? '' : ' \u00B7 ${refundCountry(r.country)?.name ?? r.country}'}',
                        style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_money(r.totalCents, r.currency, r.country)}  \u00B7  ${tr('VAT')} ${_money(r.vatCents, r.currency, r.country)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(label: Text(r.status.label), visualDensity: VisualDensity.compact),
                          _deadline(r),
                        ],
                      ),
                      if (r.status != RefundStatus.refunded)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            key: ValueKey('advance-${r.id}'),
                            onPressed: () => _advance(r),
                            child: Text(switch (r.status) {
                              RefundStatus.toStamp => 'Mark as stamped',
                              RefundStatus.stamped => 'Mark as sent for refund',
                              _ => 'Mark as refunded',
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            tr(
              'Rules differ by country and shop. The deadline here is the usual EU one (end of the third month after the month of purchase); follow the date and steps on your tax-free form. Doculoom does not claim refunds for you.',
            ),
            style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _sum(String label, int cents, String currency, Color color) => cents == 0
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ),
              Text(_money(cents, currency, ''), style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        );
}

class _EditResult {
  const _EditResult.save(this.receipt) : delete = false;
  const _EditResult.delete() : receipt = null, delete = true;
  final VatReceipt? receipt;
  final bool delete;
}

class _ReceiptEditor extends StatefulWidget {
  const _ReceiptEditor({required this.store, required this.existing, required this.pickPhoto, required this.today});
  final VatRefundStore store;
  final VatReceipt? existing;
  final Future<String?> Function(bool camera) pickPhoto;
  final DateTime today;

  @override
  State<_ReceiptEditor> createState() => _ReceiptEditorState();
}

class _ReceiptEditorState extends State<_ReceiptEditor> {
  late final _shop = TextEditingController(text: widget.existing?.store ?? '');
  late final _total = TextEditingController(text: _text(widget.existing?.totalCents));
  late final _vat = TextEditingController(text: _text(widget.existing?.vatCents));
  late final _form = TextEditingController(text: widget.existing?.formNumber ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late DateTime _date = widget.existing?.date ?? widget.today;
  late String _country = widget.existing?.country ?? '';
  late String _currency = widget.existing?.currency ?? 'EUR';
  late RefundStatus _status = widget.existing?.status ?? RefundStatus.toStamp;
  String? _photo;
  bool _photoChanged = false;
  String? _error;

  static String _text(int? cents) => cents == null || cents == 0 ? '' : '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _photo = widget.existing?.photoPath;
  }

  @override
  void dispose() {
    for (final c in [_shop, _total, _vat, _form, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _chooseCountry(String? code) {
    final c = refundCountry(code ?? '');
    setState(() {
      _country = code ?? '';
      if (c != null) _currency = c.currency;
    });
  }

  void _estimate() {
    final total = parseCents(_total.text);
    final rate = refundCountry(_country)?.vatRate;
    if (total == null || rate == null) {
      setState(() => _error = 'Enter the total and choose the country first.');
      return;
    }
    setState(() {
      _error = null;
      _vat.text = _text(vatInPrice(total, rate));
    });
  }

  Future<void> _pick(bool camera) async {
    final path = await widget.pickPhoto(camera);
    if (path == null || !mounted) return;
    final stored = await widget.store.addPhoto(path);
    if (!mounted) return;
    if (stored == null) {
      setState(() => _error = 'That file is not a picture.');
      return;
    }
    if (_photoChanged) await widget.store.deletePhoto(_photo);
    setState(() {
      _photo = stored;
      _photoChanged = true;
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _save() async {
    final total = parseCents(_total.text);
    if (total == null || total == 0) {
      setState(() => _error = 'Enter the total you paid, such as 249.90.');
      return;
    }
    final vatText = _vat.text.trim();
    final vat = vatText.isEmpty ? 0 : parseCents(vatText);
    if (vat == null) {
      setState(() => _error = 'The VAT amount is not valid. Use numbers such as 41.50.');
      return;
    }
    if (vat > total) {
      setState(() => _error = 'The VAT cannot be more than the total.');
      return;
    }
    if (_photoChanged && widget.existing?.photoPath != null && widget.existing!.photoPath != _photo) await widget.store.deletePhoto(widget.existing!.photoPath);
    final base = widget.existing ?? VatReceipt(id: widget.store.newId(), date: _date);
    if (!mounted) return;
    Navigator.of(context).pop(
      _EditResult.save(
        base.copyWith(
          store: _shop.text.trim(),
          country: _country,
          date: _date,
          totalCents: total,
          vatCents: vat,
          currency: _currency,
          status: _status,
          formNumber: _form.text.trim(),
          note: _note.text.trim(),
          photoPath: _photo,
        ),
      ),
    );
  }

  Future<void> _remove() async {
    final ok = await confirmDestructive(
      context,
      title: 'Delete this receipt?',
      message: 'The receipt and its picture are removed from this phone.',
      action: 'Delete',
    );
    if (ok && mounted) Navigator.of(context).pop(const _EditResult.delete());
  }

  Future<void> _cancel() async {
    if (_photoChanged && _photo != widget.existing?.photoPath) await widget.store.deletePhoto(_photo);
  }

  @override
  Widget build(BuildContext context) {
    final deadline = exportDeadline(_date);
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (result == null) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.existing == null ? 'New receipt' : 'Receipt'),
          actions: [if (widget.existing != null) IconButton(tooltip: tr('Delete'), icon: const Icon(AppIcons.delete), onPressed: _remove)],
        ),
        body: ListView(
          padding: contentPadding(context),
          children: [
            TextField(
              controller: _shop,
              decoration: InputDecoration(labelText: tr('Shop')),
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            DropdownButtonFormField<String>(
              key: const ValueKey('country'),
              initialValue: refundCountry(_country) == null ? null : _country,
              decoration: InputDecoration(labelText: tr('Country of purchase')),
              isExpanded: true,
              items: [for (final c in refundCountries) DropdownMenuItem(value: c.code, child: Text(c.name))],
              onChanged: _chooseCountry,
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            OutlinedButton(onPressed: _pickDate, child: Text('${tr('Date of purchase')}: ${formatDate(_date)}')),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: AppSpacing.sm),
              child: Text(
                trf('Usual deadline for the customs stamp: {date}', {'date': formatDate(deadline)}),
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _total,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('Total paid, with VAT')),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 118,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _currency,
                    decoration: InputDecoration(labelText: tr('Currency')),
                    items: [
                      for (final c in {'EUR', 'CZK', 'DKK', 'HUF', 'PLN', 'RON', 'SEK', 'CHF', 'NOK', 'GBP', _currency})
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (c) => setState(() => _currency = c ?? _currency),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _vat,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('VAT to refund (from the form)')),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: _estimate,
                  child: const Text('Estimate'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr(
                  'The estimate is the VAT inside the price at the usual standard rate. The shop\'s form shows the amount that counts; refund services keep a fee.',
                ),
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
              ),
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            DropdownButtonFormField<RefundStatus>(
              initialValue: _status,
              decoration: InputDecoration(labelText: tr('Where it stands')),
              isExpanded: true,
              items: [for (final s in RefundStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
              onChanged: (s) => setState(() => _status = s ?? _status),
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            TextField(
              controller: _form,
              decoration: InputDecoration(labelText: tr('Number on the tax-free form (optional)')),
            ),
            const SizedBox(height: AppSpacing.sm + 4),
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: tr('Note (optional)')),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_photo != null)
              Container(
                height: 160,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
                child: Image.file(File(_photo!), fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(AppIcons.gallery)),
              ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  key: const ValueKey('photo-camera'),
                  onPressed: () => _pick(true),
                  icon: const Icon(AppIcons.camera, size: 18),
                  label: Text(_photo == null ? 'Take a photo' : 'Take another photo'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  key: const ValueKey('photo-gallery'),
                  onPressed: () => _pick(false),
                  icon: const Icon(AppIcons.gallery, size: 18),
                  label: const Text('Choose a picture'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(tr(_error!), style: const TextStyle(color: AppColors.danger)),
              ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              key: const ValueKey('save-receipt'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: _save,
              child: const Text('Save receipt'),
            ),
          ],
        ),
      ),
    );
  }
}
