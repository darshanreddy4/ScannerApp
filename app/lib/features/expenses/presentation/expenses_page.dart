import 'dart:ui' show PlatformDispatcher;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../documents/domain/entities/scanned_document.dart';
import '../../documents/presentation/bloc/documents_cubit.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../../ocr/domain/ocr_engine.dart';
import '../../office/sheets/presentation/sheet_page.dart';
import '../../pdf_tools/data/pdf_picture_pages.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/expense_summary.dart';
import '../domain/money.dart';
import '../domain/receipt_reader.dart';
import '../domain/receipt_record.dart';
import 'expenses_cubit.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Where the pictures, files and saved scans come from; replaced in tests.
typedef PathsPicker = Future<List<String>> Function();
typedef ScansPicker = Future<List<BillSource>> Function(BuildContext context);

Future<List<String>> _pickImages() async {
  final files = await ImagePicker().pickMultiImage();
  return [for (final f in files) f.path];
}

Future<List<String>> _takePhoto() async {
  final photo = await ImagePicker().pickImage(source: ImageSource.camera);
  return photo == null ? const [] : [photo.path];
}

Future<List<String>> _pickFiles() async {
  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: [...ExpensesCubit.imageExtensions, 'pdf']);
  return [
    for (final f in picked)
      if (f.path != null) f.path!,
  ];
}

/// Saved scans, with those in the Receipts folder ticked, to read as bills.
Future<List<BillSource>> _pickScans(BuildContext context) async {
  final state = context.read<DocumentsCubit>().state;
  final lockedFolders = {
    for (final f in state.folders)
      if (f.locked) f.id,
  };
  final folderName = {for (final f in state.folders) f.id: f.name};
  final receiptFolders = {
    for (final f in state.folders)
      if (f.name.trim().toLowerCase() == 'receipts') f.id,
  };
  final docs =
      [
        for (final d in state.documents)
          if (!d.locked && !lockedFolders.contains(d.folderId) && d.pages.isNotEmpty) d,
      ]..sort(
        (a, b) => a.folderId != null && receiptFolders.contains(a.folderId)
            ? (b.folderId != null && receiptFolders.contains(b.folderId) ? b.updatedAt.compareTo(a.updatedAt) : -1)
            : (b.folderId != null && receiptFolders.contains(b.folderId) ? 1 : b.updatedAt.compareTo(a.updatedAt)),
      );
  final chosen = await showModalBottomSheet<List<ScannedDocument>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ScanSheet(
      documents: docs,
      preselected: {
        for (final d in docs)
          if (d.folderId != null && receiptFolders.contains(d.folderId)) d.id,
      },
      folderName: folderName,
    ),
  );
  return [
    for (final d in chosen ?? const <ScannedDocument>[]) (label: d.title, pages: [for (final pg in d.pages) pg.imagePath]),
  ];
}

/// Many bills in, one workbook out: each bill becomes a row (shop, date, subtotal, tax, total), the rows are added up by month and by kind of
/// spending, and the result is shared as Excel or CSV.
class ExpensesPage extends StatelessWidget {
  const ExpensesPage({
    super.key,
    this.engine,
    this.pdfPages,
    this.pickImages = _pickImages,
    this.takePhoto = _takePhoto,
    this.pickFiles = _pickFiles,
    this.pickScans = _pickScans,
    this.country,
  });

  /// For tests; the phone's text reader is used otherwise.
  final OcrEngine? engine;
  final PdfPicturePages Function()? pdfPages;
  final PathsPicker pickImages;
  final PathsPicker takePhoto;
  final PathsPicker pickFiles;
  final ScansPicker pickScans;

  /// The region that decides the first currency; the phone's own is used when null.
  final String? country;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => ExpensesCubit(
      engine: engine ?? sl<OcrEngine>(),
      outputDir: getTemporaryDirectory,
      script: context.read<SettingsCubit>().state.ocrScript,
      defaultCurrency: currencyForCountry(country ?? PlatformDispatcher.instance.locale.countryCode),
      pdfPages: pdfPages,
    ),
    child: _ExpensesView(page: this),
  );
}

class _ExpensesView extends StatelessWidget {
  const _ExpensesView({required this.page});
  final ExpensesPage page;

  Future<void> _add(BuildContext context, PathsPicker pick) async {
    try {
      final paths = await pick();
      if (paths.isEmpty || !context.mounted) return;
      await context.read<ExpensesCubit>().addFiles(paths);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The pictures or files could not be opened.'));
    }
  }

  Future<void> _addScans(BuildContext context) async {
    final cubit = context.read<ExpensesCubit>();
    try {
      final sources = await page.pickScans(context);
      if (sources.isEmpty) return;
      await cubit.addScans(sources);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The saved scans could not be opened.'));
    }
  }

  Future<void> _edit(BuildContext context, ReceiptRecord record) async {
    final cubit = context.read<ExpensesCubit>();
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _EditSheet(record: record),
    );
    if (result == null) return;
    if (result.record != null) {
      cubit.replace(result.record!);
    } else {
      cubit.remove(record.id);
    }
  }

  Future<void> _open(BuildContext context) async {
    final path = await context.read<ExpensesCubit>().writeXlsx();
    if (path != null && context.mounted) await context.push('/sheet', extra: SheetArgs(path: path));
  }

  Future<void> _share(BuildContext context, {required bool excel}) async {
    final cubit = context.read<ExpensesCubit>();
    final path = excel ? await cubit.writeXlsx() : await cubit.writeCsv();
    if (path == null || !context.mounted) return;
    final failure = (await sl<ShareService>().shareFile(path: path, mimeType: excel ? _xlsxMime : 'text/csv', subject: 'Expenses')).failureOrNull;
    if (failure != null && context.mounted) showFailure(context, failure);
  }

  Future<void> _save(BuildContext context) async {
    final path = await context.read<ExpensesCubit>().writeXlsx();
    if (path == null || !context.mounted) return;
    final result = await sl<SaveService>().saveToFiles(
      sourcePath: path,
      fileName: p.basename(path).replaceAll(RegExp(r'_\d{10,}(?=\.xlsx$)'), ''),
      mimeType: _xlsxMime,
    );
    if (!context.mounted) return;
    final failure = result.failureOrNull;
    if (failure != null) {
      showFailure(context, failure);
    } else if (result.valueOrNull == true) {
      showMessage(context, 'Saved');
    }
  }

  Future<void> _copyTotals(BuildContext context, ExpenseSummary summary) async {
    final text = [for (final c in summary.currencies) 'Total ${formatMoney(c.total, c.currency)} (${c.count} bills)'].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showMessage(context, 'Totals copied');
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ExpensesCubit, ExpensesState>(
    builder: (context, state) {
      final cubit = context.read<ExpensesCubit>();
      final summary = state.summary;
      final dupes = state.duplicates;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Receipts and expenses'),
          actions: [
            if (state.hasRecords && !state.reading) ...[
              IconButton(
                key: const ValueKey('expenses-copy'),
                tooltip: tr('Copy totals'),
                icon: const Icon(AppIcons.copy),
                onPressed: () => _copyTotals(context, summary),
              ),
              TextButton(key: const ValueKey('expenses-clear'), onPressed: cubit.clear, child: const Text('Clear')),
            ],
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: contentPadding(context, base: AppSpacing.md, maxWidth: 720),
            children: [
              _AddCard(
                state: state,
                onImages: () => _add(context, page.pickImages),
                onCamera: () => _add(context, page.takePhoto),
                onFiles: () => _add(context, page.pickFiles),
                onScans: () => _addScans(context),
              ),
              if (state.reading) ...[const SizedBox(height: AppSpacing.md), _Reading(state: state)],
              for (final note in state.notes)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    note,
                    key: const ValueKey('expenses-note'),
                    style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
                  ),
                ),
              if (state.failure != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Text(
                    state.failure!.message,
                    key: const ValueKey('expenses-failure'),
                    style: const TextStyle(color: AppColors.danger, height: 1.4),
                  ),
                ),
              if (state.hasRecords) ...[
                for (final c in summary.currencies) ...[
                  const SizedBox(height: AppSpacing.md),
                  _SummaryCard(summary: c, several: summary.currencies.length > 1),
                ],
                if (summary.withoutTotal > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      summary.withoutTotal == 1
                          ? '1 bill has no total, so it is not in the sums. Tap it and type the total.'
                          : '${summary.withoutTotal} bills have no total, so they are not in the sums. Tap each and type the total.',
                      key: const ValueKey('expenses-untotalled'),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.warning, height: 1.4),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Text('${state.records.length} ${state.records.length == 1 ? 'bill' : 'bills'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.sm),
                for (final r in state.records)
                  _BillTile(record: r, duplicate: dupes.contains(r.id), onTap: () => _edit(context, r), onRemove: () => cubit.remove(r.id)),
              ],
              const SizedBox(height: AppSpacing.md),
              const _Note(),
            ],
          ),
        ),
        bottomNavigationBar: state.hasRecords && !state.reading
            ? _Actions(
                onOpen: () => _open(context),
                onExcel: () => _share(context, excel: true),
                onCsv: () => _share(context, excel: false),
                onSave: () => _save(context),
              )
            : null,
      );
    },
  );
}

class _AddCard extends StatelessWidget {
  const _AddCard({required this.state, required this.onImages, required this.onCamera, required this.onFiles, required this.onScans});
  final ExpensesState state;
  final VoidCallback onImages;
  final VoidCallback onCamera;
  final VoidCallback onFiles;
  final VoidCallback onScans;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ExpensesCubit>();
    final busy = state.reading;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.hasRecords ? 'Add more bills' : 'Add your bills', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Photos of bills and receipts: each picture is one bill, each page of a PDF is one bill, and each saved scan is one bill.',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  key: const ValueKey('expenses-images'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: busy ? null : onImages,
                  icon: const Icon(AppIcons.gallery, size: 18),
                  label: const Text('Pictures'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('expenses-camera'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: busy ? null : onCamera,
                  icon: const Icon(AppIcons.camera, size: 18),
                  label: const Text('Take a photo'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('expenses-files'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: busy ? null : onFiles,
                  icon: const Icon(AppIcons.importFile, size: 18),
                  label: const Text('PDFs and files'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('expenses-scans'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: busy ? null : onScans,
                  icon: const Icon(AppIcons.library, size: 18),
                  label: const Text('My scans'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Expanded(
                  child: Text('Currency when a bill shows none', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                ),
                DropdownButton<String>(
                  key: const ValueKey('expenses-currency'),
                  value: state.defaultCurrency,
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('None')),
                    for (final c in expenseCurrencies) DropdownMenuItem(value: c, child: Text(currencySign(c) == c ? c : '$c  ${currencySign(c)}')),
                  ],
                  onChanged: busy ? null : (v) => cubit.setDefaultCurrency(v ?? ''),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.state});
  final ExpensesState state;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.total > 1 ? 'Reading ${state.label} (${(state.done + 1).clamp(1, state.total)} of ${state.total})' : 'Reading ${state.label}',
            key: const ValueKey('expenses-progress'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(value: state.total > 1 ? state.done / state.total : null),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(key: const ValueKey('expenses-cancel'), onPressed: context.read<ExpensesCubit>().cancel, child: const Text('Stop')),
          ),
        ],
      ),
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.several});
  final CurrencySummary summary;
  final bool several;

  @override
  Widget build(BuildContext context) {
    final code = summary.currency.isEmpty ? 'none' : summary.currency;
    final biggestMonth = summary.months.fold<double>(0, (m, e) => e.total > m ? e.total : m);
    final biggestKind = summary.categories.fold<double>(0, (m, e) => e.total > m ? e.total : m);
    return Card(
      key: ValueKey('expenses-summary-$code'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              several ? 'Total spent (${summary.currency.isEmpty ? 'no currency' : summary.currency})' : 'Total spent',
              style: const TextStyle(color: AppColors.inkMuted),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                formatMoney(summary.total, summary.currency),
                key: ValueKey('expenses-total-$code'),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.ink),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${summary.count} ${summary.count == 1 ? 'bill' : 'bills'}  ·  tax ${formatMoney(summary.tax, summary.currency)}  ·  average ${formatMoney(summary.average, summary.currency)}',
              key: ValueKey('expenses-figures-$code'),
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('By month', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            for (final m in summary.months)
              _Bar(
                key: ValueKey('expenses-month-$code-${m.month.isEmpty ? 'none' : m.month}'),
                label: m.month.isEmpty ? 'No date' : monthYearLabel(m.month),
                detail: m.count == 1 ? '1 bill' : '${m.count} bills',
                value: formatMoney(m.total, summary.currency),
                fraction: biggestMonth <= 0 ? 0 : m.total / biggestMonth,
              ),
            const SizedBox(height: AppSpacing.sm),
            const Text('By kind of spending', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            for (final k in summary.categories)
              _Bar(
                key: ValueKey('expenses-kind-$code-${k.category.name}'),
                label: k.category.label,
                detail: k.count == 1 ? '1 bill' : '${k.count} bills',
                value: formatMoney(k.total, summary.currency),
                fraction: biggestKind <= 0 ? 0 : k.total / biggestKind,
              ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({super.key, required this.label, required this.detail, required this.value, required this.fraction});
  final String label;
  final String detail;
  final String value;
  final double fraction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('$label  ·  $detail', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: fraction.clamp(0.0, 1.0), minHeight: 6, backgroundColor: AppColors.border),
        ),
      ],
    ),
  );
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.record, required this.duplicate, required this.onTap, required this.onRemove});
  final ReceiptRecord record;
  final bool duplicate;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final notes = [for (final n in record.notes) n.message, if (duplicate) ReceiptNote.duplicate.message];
    return Card(
      key: ValueKey('expenses-bill-${record.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.vendor.isEmpty ? 'Unknown shop' : record.vendor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${record.date == null ? 'No date' : formatDate(record.date!)}  ·  ${record.category.label}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                    ),
                    for (final n in notes)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(AppIcons.warning, size: 13, color: AppColors.warning),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(n, style: const TextStyle(fontSize: 12, color: AppColors.warning, height: 1.3)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  record.total == null ? 'No total' : formatMoney(record.total!, record.currency),
                  key: ValueKey('expenses-amount-${record.id}'),
                  textAlign: TextAlign.end,
                  style: TextStyle(fontWeight: FontWeight.w700, color: record.total == null ? AppColors.warning : AppColors.ink),
                ),
              ),
              IconButton(
                key: ValueKey('expenses-remove-${record.id}'),
                tooltip: tr('Remove this bill'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(AppIcons.delete, size: 18),
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditResult {
  const _EditResult.save(ReceiptRecord this.record);
  const _EditResult.delete() : record = null;
  final ReceiptRecord? record;
}

/// Corrects what was read from one bill; the check under the fields shows at once whether the parts add up.
class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.record});
  final ReceiptRecord record;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _vendor = TextEditingController(text: widget.record.vendor);
  late final _subtotal = TextEditingController(text: _text(widget.record.subtotal));
  late final _discount = TextEditingController(text: _text(widget.record.discount));
  late final _tax = TextEditingController(text: _text(widget.record.tax));
  late final _tip = TextEditingController(text: _text(widget.record.tip));
  late final _total = TextEditingController(text: _text(widget.record.total));
  late DateTime? _date = widget.record.date;
  late String _currency = widget.record.currency;
  late ExpenseCategory _category = widget.record.category;

  static String _text(double? v) => v == null ? '' : v.toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in [_vendor, _subtotal, _discount, _tax, _tip, _total]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The number in a field: null when empty, and [bad] set when there is text that is no amount.
  (double?, bool) _read(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return (null, false);
    final v = parseAmount(t, allowBare: true);
    return (v, v == null);
  }

  bool get _valid => [_subtotal, _discount, _tax, _tip, _total].every((c) => !_read(c).$2);

  ReceiptRecord _built() {
    final old = widget.record;
    final total = _read(_total).$1, tax = _read(_tax).$1;
    return old.copyWith(
      vendor: _vendor.text.trim(),
      date: _date,
      currency: _currency,
      category: _category,
      subtotal: _read(_subtotal).$1,
      discount: _read(_discount).$1,
      tax: tax,
      tip: _read(_tip).$1,
      total: total,
      totalWorkedOut: total == old.total ? old.totalWorkedOut : false,
      totalGuessed: total == old.total ? old.totalGuessed : false,
      taxWorkedOut: tax == old.tax ? old.taxWorkedOut : false,
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: _date ?? now, firstDate: DateTime(2000), lastDate: DateTime(now.year + 1, 12, 31));
    if (picked != null) setState(() => _date = picked);
  }

  Widget _amount(String key, String label, TextEditingController c) => TextField(
    key: ValueKey(key),
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
    decoration: InputDecoration(labelText: label, errorText: _read(c).$2 ? 'Not an amount' : null),
    onChanged: (_) => setState(() {}),
  );

  @override
  Widget build(BuildContext context) {
    final preview = _valid ? _built() : null;
    final notes = preview == null
        ? const <String>[]
        : [
            for (final n in preview.notes)
              if (n != ReceiptNote.missingDate) n.message,
          ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Check this bill', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(
              widget.record.source,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey('expense-vendor'),
              controller: _vendor,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Shop')),
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              key: const ValueKey('expense-date'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(AppIcons.calendar),
              title: Text(_date == null ? 'No date. Tap to choose.' : formatDate(_date!)),
              onTap: _pickDate,
            ),
            _Pair(
              first: DropdownButtonFormField<ExpenseCategory>(
                key: const ValueKey('expense-category'),
                initialValue: _category,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Kind of spending')),
                items: [
                  for (final c in ExpenseCategory.values)
                    DropdownMenuItem(
                      value: c,
                      child: Text(c.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              secondWidth: 112,
              second: DropdownButtonFormField<String>(
                key: const ValueKey('expense-currency'),
                initialValue: _currency,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Currency')),
                items: [
                  const DropdownMenuItem(value: '', child: Text('None')),
                  for (final c in {...expenseCurrencies, if (_currency.isNotEmpty) _currency}) DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _currency = v ?? ''),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Pair(first: _amount('expense-subtotal', 'Subtotal', _subtotal), second: _amount('expense-discount', 'Discount', _discount)),
            const SizedBox(height: AppSpacing.sm),
            _Pair(first: _amount('expense-tax', 'Tax', _tax), second: _amount('expense-tip', 'Tip and charges', _tip)),
            const SizedBox(height: AppSpacing.sm),
            _amount('expense-total', 'Total', _total),
            const SizedBox(height: AppSpacing.sm),
            if (preview != null && notes.isEmpty && preview.total != null)
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(AppIcons.check, size: 16, color: AppColors.success),
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'The amounts add up.',
                      key: ValueKey('expense-ok'),
                      style: TextStyle(fontSize: 12.5, color: AppColors.success),
                    ),
                  ),
                ],
              ),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  n,
                  key: const ValueKey('expense-check'),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.warning, height: 1.3),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                TextButton(
                  key: const ValueKey('expense-delete'),
                  onPressed: () => Navigator.pop(context, const _EditResult.delete()),
                  child: const Text('Remove bill'),
                ),
                FilledButton(
                  key: const ValueKey('expense-save'),
                  onPressed: _valid ? () => Navigator.pop(context, _EditResult.save(_built())) : null,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Two fields side by side, or one above the other on a narrow screen or with large text.
class _Pair extends StatelessWidget {
  const _Pair({required this.first, required this.second, this.secondWidth});
  final Widget first;
  final Widget second;
  final double? secondWidth;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 380 || MediaQuery.textScalerOf(context).scale(1) > 1.2;
    if (narrow) {
      return Column(
        children: [
          first,
          const SizedBox(height: AppSpacing.sm),
          second,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: AppSpacing.sm),
        secondWidth == null ? Expanded(child: second) : SizedBox(width: secondWidth, child: second),
      ],
    );
  }
}

/// Saved scans to choose from; those in the Receipts folder start ticked.
class _ScanSheet extends StatefulWidget {
  const _ScanSheet({required this.documents, required this.preselected, required this.folderName});
  final List<ScannedDocument> documents;
  final Set<String> preselected;
  final Map<String, String> folderName;

  @override
  State<_ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<_ScanSheet> {
  late final Set<String> _chosen = {...widget.preselected};

  @override
  Widget build(BuildContext context) {
    final docs = widget.documents;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(docs.isEmpty ? 'No saved scans' : 'Choose the scans that are bills', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ),
        Expanded(
          child: docs.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'Scan a bill first, or choose pictures. Scans of receipts are filed in the Receipts folder.',
                    key: ValueKey('expenses-scans-empty'),
                  ),
                )
              : ListView(
                  children: [
                    for (final d in docs)
                      CheckboxListTile(
                        key: ValueKey('expenses-scan-${d.id}'),
                        value: _chosen.contains(d.id),
                        title: Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            if (d.folderId != null && widget.folderName[d.folderId] != null) widget.folderName[d.folderId]!,
                            formatDate(d.updatedAt),
                            pagesLabel(d.pages.length),
                          ].join('  ·  '),
                        ),
                        onChanged: (v) => setState(() => v == true ? _chosen.add(d.id) : _chosen.remove(d.id)),
                      ),
                  ],
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('expenses-scans-read'),
                onPressed: _chosen.isEmpty
                    ? null
                    : () => Navigator.pop(context, [
                        for (final d in docs)
                          if (_chosen.contains(d.id)) d,
                      ]),
                child: Text(_chosen.length == 1 ? 'Read 1 scan' : 'Read ${_chosen.length} scans'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.onOpen, required this.onExcel, required this.onCsv, required this.onSave});
  final VoidCallback onOpen;
  final VoidCallback onExcel;
  final VoidCallback onCsv;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 6,
    color: Theme.of(context).colorScheme.surface,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              key: const ValueKey('expenses-share-xlsx'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onExcel,
              icon: const Icon(AppIcons.sheet, size: 18),
              label: const Text('Share Excel'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('expenses-open'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onOpen,
              icon: const Icon(AppIcons.edit, size: 18),
              label: const Text('Open to edit'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('expenses-share-csv'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onCsv,
              icon: const Icon(AppIcons.share, size: 18),
              label: const Text('Share CSV'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('expenses-save'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onSave,
              icon: const Icon(AppIcons.storage, size: 18),
              label: const Text('Save to Files'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note();

  @override
  Widget build(BuildContext context) => const Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.shield, size: 20, color: AppColors.success),
          SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Text(
              'Bills are read on this phone and never uploaded. The text reader can make mistakes, so look at the notes under each bill and check the totals before you rely on them.',
              style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.inkMuted),
            ),
          ),
        ],
      ),
    ),
  );
}
