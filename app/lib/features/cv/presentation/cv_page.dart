import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;

import '../../../app/di.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/region.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../../importer/domain/importer.dart';
import '../../pdf_tools/data/pdf_picture_pages.dart';
import '../../reader/presentation/reader_page.dart';
import '../data/cv_pdf.dart';
import '../data/cv_store.dart';
import '../domain/cv.dart';
import 'cv_design_picker.dart';

class _EntryFields {
  _EntryFields([CvEntry e = const CvEntry()])
    : title = TextEditingController(text: e.title),
      organisation = TextEditingController(text: e.organisation),
      place = TextEditingController(text: e.place),
      from = TextEditingController(text: e.from),
      to = TextEditingController(text: e.to),
      description = TextEditingController(text: e.description),
      current = e.to.trim().isEmpty && e.from.trim().isNotEmpty;
  final TextEditingController title, organisation, place, from, to, description;

  /// Still working or studying there: the end date stays empty and the CV says "present".
  bool current;

  CvEntry get value => CvEntry(
    title: title.text,
    organisation: organisation.text,
    place: place.text,
    from: from.text,
    to: current ? '' : to.text,
    description: description.text,
  );

  void dispose() {
    for (final c in [title, organisation, place, from, to, description]) {
      c.dispose();
    }
  }
}

class _LanguageFields {
  _LanguageFields([CvLanguage l = const CvLanguage(name: '')]) : name = TextEditingController(text: l.name), level = l.level;
  final TextEditingController name;
  String level;
}

Future<Uint8List> _loadAsset(String path) async => (await rootBundle.load(path)).buffer.asUint8List();

Future<String?> _pickPhoto() async => (await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600))?.path;

/// Writes a CV in the style of the European format and makes it a PDF. The CV and the photo stay on this phone.
class CvPage extends StatefulWidget {
  const CvPage({
    super.key,
    this.workDir = getTemporaryDirectory,
    this.appDir = getApplicationDocumentsDirectory,
    this.loadAsset = _loadAsset,
    this.pickPhoto = _pickPhoto,
    this.pdfPages = PdfxPicturePages.new,
  });
  final Future<Directory> Function() workDir;
  final Future<Directory> Function() appDir;
  final Future<Uint8List> Function(String asset) loadAsset;
  final Future<String?> Function() pickPhoto;
  final PdfPicturePages Function() pdfPages;

  @override
  State<CvPage> createState() => _CvPageState();
}

class _CvPageState extends State<CvPage> {
  late final CvStore _store = CvStore(appDir: widget.appDir);
  final _name = TextEditingController();
  final _headline = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _website = TextEditingController();
  final _birth = TextEditingController();
  final _nationality = TextEditingController();
  final _summary = TextEditingController();
  final _skills = TextEditingController();
  final _work = <_EntryFields>[];
  final _education = <_EntryFields>[];
  final _languages = <_LanguageFields>[];
  String _language = 'en';
  String _template = 'europe';
  int _accent = defaultCvAccent;
  bool _submitted = false;
  final _keys = <String, GlobalKey>{};
  Uint8List? _photo;
  Timer? _timer;
  bool _loaded = false;
  bool _busy = false;
  String? _made;

  List<TextEditingController> get _simple => [_name, _headline, _email, _phone, _address, _website, _birth, _nationality, _summary, _skills];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await _store.load();
    final photo = await _store.loadPhoto();
    if (!mounted) return;
    setState(() {
      _name.text = d.name;
      _headline.text = d.headline;
      _email.text = d.email;
      _phone.text = d.phone;
      _address.text = d.address;
      _website.text = d.website;
      _birth.text = d.birthDate;
      _nationality.text = d.nationality;
      _summary.text = d.summary;
      _skills.text = d.skills.join(', ');
      _work
        ..clear()
        ..addAll(d.work.isEmpty ? [_EntryFields()] : d.work.map(_EntryFields.new));
      _education
        ..clear()
        ..addAll(d.education.isEmpty ? [_EntryFields()] : d.education.map(_EntryFields.new));
      _languages
        ..clear()
        ..addAll(d.languages.map(_LanguageFields.new));
      _language = d.language;
      _template = d.template;
      _accent = d.accent;
      _photo = photo;
      _loaded = true;
    });
  }

  CvData get _data => CvData(
    name: _name.text.trim(),
    headline: _headline.text.trim(),
    email: _email.text.trim(),
    phone: _phone.text.trim(),
    address: _address.text.trim(),
    website: _website.text.trim(),
    birthDate: _birth.text.trim(),
    nationality: _nationality.text.trim(),
    summary: _summary.text,
    work: [for (final e in _work) e.value],
    education: [for (final e in _education) e.value],
    skills: splitSkills(_skills.text),
    languages: [
      for (final l in _languages)
        if (l.name.text.trim().isNotEmpty) CvLanguage(name: l.name.text.trim(), level: l.level),
    ],
    language: _language,
    template: _template,
    accent: _accent,
  );

  /// What is wrong, from the checks of the CV itself and the end dates that are neither filled in nor marked as current.
  List<CvIssue> get _issues {
    final out = cvIssues(_data);
    void ends(String kind, List<_EntryFields> list) {
      for (final (i, e) in list.indexed) {
        if (!e.current &&
            e.from.text.trim().isNotEmpty &&
            e.to.text.trim().isEmpty &&
            !out.any((x) => x.field == '$kind.$i.to' || x.field == '$kind.$i.from')) {
          out.add(CvIssue('$kind.$i.to', 'Enter the end date, or tick that you are still there.'));
        }
      }
    }

    ends('work', _work);
    ends('education', _education);
    return out;
  }

  String? _error(String field) {
    if (!_submitted) return null;
    final i = _issues.where((x) => x.field == field).firstOrNull;
    if (i == null) return null;
    if (i.message.startsWith('The text is too long')) {
      final max = field == 'summary' ? cvMaxSummary : (field.endsWith('.description') ? cvMaxDescription : (field == 'skills' ? 400 : 80));
      return trf(i.message, {'n': max});
    }
    return tr(i.message);
  }

  void _changed() {
    _made = null;
    if (!_loaded) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), () => _store.save(_data));
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_loaded) unawaited(_store.save(_data));
    for (final c in _simple) {
      c.dispose();
    }
    for (final e in [..._work, ..._education]) {
      e.dispose();
    }
    for (final l in _languages) {
      l.name.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final path = await widget.pickPhoto();
    if (path == null || !mounted) return;
    try {
      final jpeg = await compute(shrinkPhoto, await File(path).readAsBytes());
      await _store.savePhoto(jpeg);
      if (mounted) {
        setState(() {
          _photo = jpeg;
          _made = null;
        });
      }
    } on Object {
      if (mounted) showMessage(context, 'That picture could not be used.');
    }
  }

  Future<void> _removePhoto() async {
    await _store.deletePhoto();
    if (mounted) {
      setState(() {
        _photo = null;
        _made = null;
      });
    }
  }

  Future<void> _create() async {
    setState(() => _submitted = true);
    final issues = _issues;
    if (issues.isNotEmpty) {
      showMessage(context, 'Fix the marked fields, then try again.');
      final first = switch (issues.first.field) {
        'contact' => 'email',
        'content' => 'summary',
        final f => f,
      };
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[first]?.currentContext;
        if (ctx != null) unawaited(Scrollable.ensureVisible(ctx, alignment: 0.15, duration: const Duration(milliseconds: 250)));
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final d = tidyCv(_data);
      _writeDates(d);
      await _store.save(_data);
      final bytes = await buildCvPdf(d, loadAsset: widget.loadAsset, photo: _photo, format: Region.letter ? PdfPageFormat.letter : PdfPageFormat.a4);
      final dir = await Directory(p.join((await widget.workDir()).path, 'cv')).create(recursive: true);
      final safe = d.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
      final file = await File(p.join(dir.path, 'CV_$safe.pdf')).writeAsBytes(bytes, flush: true);
      if (mounted) setState(() => _made = file.path);
    } on Object catch (e) {
      debugPrint('CV could not be made: $e');
      if (mounted) showMessage(context, 'The CV could not be made. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows the dates the way the CV writes them (03/2019, 25/03/1990).
  void _writeDates(CvData d) {
    _birth.text = d.birthDate;
    for (final (i, e) in _work.where((e) => !e.value.isEmpty).indexed) {
      e.from.text = d.work[i].from;
      if (!e.current) e.to.text = d.work[i].to;
    }
    for (final (i, e) in _education.where((e) => !e.value.isEmpty).indexed) {
      e.from.text = d.education[i].from;
      if (!e.current) e.to.text = d.education[i].to;
    }
  }

  Future<void> _share() async {
    final r = await sl<ShareService>().shareFile(path: _made!, mimeType: 'application/pdf', subject: p.basename(_made!));
    if (mounted && r.failureOrNull != null) showFailure(context, r.failureOrNull!);
  }

  Future<void> _saveToFiles() async {
    final r = await sl<SaveService>().saveToFiles(sourcePath: _made!, fileName: p.basename(_made!), mimeType: 'application/pdf');
    if (!mounted) return;
    final failure = r.failureOrNull;
    if (failure != null) {
      showFailure(context, failure);
    } else if (r.valueOrNull == true) {
      showMessage(context, 'Saved');
    }
  }

  /// Draws every page of the CV as a picture, [width] pixels wide.
  Future<List<Uint8List>> _pages(int width, {required bool png}) async {
    final pages = widget.pdfPages();
    try {
      final count = await pages.open(_made!);
      return [for (var i = 0; i < count; i++) await pages.render(i, width: width, png: png)];
    } finally {
      await pages.close();
    }
  }

  Future<void> _preview() async {
    try {
      final images = await _pages(1000, png: true);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Preview'),
              leading: IconButton(key: const ValueKey('preview-close'), icon: const Icon(AppIcons.close), onPressed: () => Navigator.pop(context)),
            ),
            body: ListView(
              key: const ValueKey('preview-pages'),
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                for (final b in images)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                      ),
                      child: InteractiveViewer(child: Image.memory(b)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } on Object {
      if (mounted) showMessage(context, 'The preview could not be shown.');
    }
  }

  Future<void> _asPictures() async {
    try {
      final images = await _pages(1654, png: false);
      final dir = await Directory(p.join((await widget.workDir()).path, 'cv')).create(recursive: true);
      final base = p.basenameWithoutExtension(_made!);
      final paths = <String>[];
      for (final (i, b) in images.indexed) {
        paths.add((await File(p.join(dir.path, '${base}_${i + 1}.jpg')).writeAsBytes(b, flush: true)).path);
      }
      final r = await sl<ShareService>().shareFiles(paths: paths, mimeType: 'image/jpeg', subject: base);
      if (mounted && r.failureOrNull != null) showFailure(context, r.failureOrNull!);
    } on Object {
      if (mounted) showMessage(context, 'The pictures could not be made.');
    }
  }

  Widget _tf(
    TextEditingController c,
    String label, {
    String? field,
    bool required = false,
    TextInputType? keyboard,
    int maxLines = 1,
    int? maxLength,
    String? hint,
    bool enabled = true,
    List<TextInputFormatter>? formatters,
    Widget? suffix,
    TextCapitalization caps = TextCapitalization.sentences,
  }) {
    final field0 = field ?? '';
    final tf = TextField(
      controller: c,
      enabled: enabled,
      keyboardType: keyboard,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: formatters,
      textCapitalization: caps,
      onChanged: (_) => _changed(),
      decoration: InputDecoration(
        labelText: required ? '${tr(label)} *' : tr(label),
        hintText: hint,
        errorText: field0.isEmpty ? null : (_error(field0) ?? (field0 == 'email' || field0 == 'phone' ? _contactError : null)),
        errorMaxLines: 3,
        counterText: '',
        suffixIcon: suffix,
        alignLabelWithHint: maxLines > 1,
      ),
    );
    return field0.isEmpty ? tf : KeyedSubtree(key: _keys.putIfAbsent(field0, GlobalKey.new), child: tf);
  }

  /// "Email or phone" is one rule for two fields: both show it until one is filled in.
  String? get _contactError => _submitted && _email.text.trim().isEmpty && _phone.text.trim().isEmpty ? _error('contact') : null;

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final initial = parseCvBirthDate(_birth.text) ?? DateTime(now.year - 30, 1, 1);
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (d == null || !mounted) return;
    _birth.text = formatCvBirthDate(d);
    _changed();
  }

  static final _dateChars = [FilteringTextInputFormatter.allow(RegExp(r'[0-9/.\-]'))];

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

  Widget _entries(
    String kind,
    String headLabel,
    String addLabel,
    List<_EntryFields> list, {
    required String titleLabel,
    required String orgLabel,
    required String currentLabel,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (i, e) in list.indexed)
        Container(
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
                    child: Text(trf('$headLabel {n}', {'n': i + 1}), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (list.length > 1 || !e.value.isEmpty)
                    IconButton(
                      tooltip: tr('Remove'),
                      icon: const Icon(AppIcons.delete, size: 20, color: AppColors.danger),
                      onPressed: () {
                        list.removeAt(i).dispose();
                        if (list.isEmpty) list.add(_EntryFields());
                        _changed();
                      },
                    ),
                ],
              ),
              _tf(e.title, titleLabel, field: '$kind.$i.title', required: true),
              _gap(),
              _tf(e.organisation, orgLabel, field: '$kind.$i.organisation'),
              _gap(),
              _tf(e.place, 'Place (optional)', field: '$kind.$i.place'),
              _gap(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _tf(
                      e.from,
                      'From (03/2019)',
                      field: '$kind.$i.from',
                      required: true,
                      hint: 'MM/YYYY',
                      formatters: _dateChars,
                      maxLength: 7,
                      keyboard: TextInputType.datetime,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _tf(
                      e.to,
                      'To (empty: present)',
                      field: '$kind.$i.to',
                      required: !e.current,
                      hint: e.current ? tr('present') : 'MM/YYYY',
                      enabled: !e.current,
                      formatters: _dateChars,
                      maxLength: 7,
                      keyboard: TextInputType.datetime,
                    ),
                  ),
                ],
              ),
              CheckboxListTile(
                key: ValueKey('$kind-current-$i'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: e.current,
                onChanged: (v) {
                  e.current = v ?? false;
                  if (e.current) e.to.clear();
                  _changed();
                },
                title: Text(currentLabel),
              ),
              _tf(e.description, 'What you did (optional)', field: '$kind.$i.description', maxLines: 3, maxLength: cvMaxDescription),
            ],
          ),
        ),
      OutlinedButton.icon(
        onPressed: () {
          list.add(_EntryFields());
          _changed();
        },
        icon: const Icon(Icons.add, size: 18),
        label: Text(addLabel),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CV maker')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: contentPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Write your CV once and make it a PDF in a clear European style. What you type is kept on this phone and nothing is uploaded. This is not the official Europass document.',
                    style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Fields marked * are required: your name, an email address or a phone number, and at least one job, course or profile text. Write dates as MM/YYYY (or just the year), and the date of birth as DD/MM/YYYY.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _section('About you', [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppColors.border,
                          backgroundImage: _photo == null ? null : MemoryImage(_photo!),
                          child: _photo == null ? const Icon(AppIcons.user, color: AppColors.inkMuted) : null,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Wrap(
                            spacing: AppSpacing.sm,
                            children: [
                              OutlinedButton(onPressed: _addPhoto, child: Text(_photo == null ? 'Add a photo' : 'Change photo')),
                              if (_photo != null) TextButton(onPressed: _removePhoto, child: const Text('Remove photo')),
                            ],
                          ),
                        ),
                      ],
                    ),
                    _gap(),
                    _tf(_name, 'Full name', field: 'name', required: true, maxLength: 80),
                    _gap(),
                    _tf(_headline, 'Job title or what you look for (optional)', field: 'headline', maxLength: 80),
                    _gap(),
                    _tf(_email, 'Email', field: 'email', required: true, keyboard: TextInputType.emailAddress, caps: TextCapitalization.none),
                    _gap(),
                    _tf(_phone, 'Phone', field: 'phone', required: true, keyboard: TextInputType.phone, hint: '+49 170 1234567'),
                    _gap(),
                    _tf(_address, 'Address (optional)', field: 'address'),
                    _gap(),
                    _tf(_website, 'Website or profile link (optional)', field: 'website', keyboard: TextInputType.url, caps: TextCapitalization.none),
                    _gap(),
                    _tf(
                      _birth,
                      'Date of birth (optional)',
                      field: 'birth',
                      hint: 'DD/MM/YYYY',
                      keyboard: TextInputType.datetime,
                      maxLength: 10,
                      formatters: _dateChars,
                      suffix: IconButton(
                        key: const ValueKey('pick-birth'),
                        tooltip: tr('Date of birth (optional)'),
                        icon: const Icon(Icons.calendar_month_outlined),
                        onPressed: _pickBirth,
                      ),
                    ),
                    _gap(),
                    _tf(_nationality, 'Nationality (optional)', field: 'nationality'),
                  ]),
                  _section('Profile', [_tf(_summary, 'A few lines about you (optional)', field: 'summary', maxLines: 4, maxLength: cvMaxSummary)]),
                  _section('Work experience', [
                    _entries('work', 'Job', 'Add a job', _work, titleLabel: 'Job title', orgLabel: 'Employer', currentLabel: tr('I still work here')),
                  ]),
                  _section('Education and training', [
                    _entries(
                      'education',
                      'Course',
                      'Add a course',
                      _education,
                      titleLabel: 'Qualification or course',
                      orgLabel: 'School or university',
                      currentLabel: tr('I still study here'),
                    ),
                  ]),
                  _section('Languages', [
                    for (final (i, l) in _languages.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Row(
                          children: [
                            Expanded(flex: 3, child: _tf(l.name, 'Language', field: 'language.$i')),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: l.level,
                                decoration: InputDecoration(labelText: tr('Level')),
                                items: [for (final v in cvLanguageLevels) DropdownMenuItem(value: v, child: Text(v == 'Native' ? tr('Mother tongue') : v))],
                                onChanged: (v) {
                                  l.level = v ?? l.level;
                                  _changed();
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: tr('Remove'),
                              icon: const Icon(AppIcons.delete, size: 20, color: AppColors.danger),
                              onPressed: () {
                                _languages.removeAt(i).name.dispose();
                                _changed();
                              },
                            ),
                          ],
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () {
                        _languages.add(_LanguageFields());
                        _changed();
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add a language'),
                    ),
                    const SizedBox(height: 4),
                    const Text('A1 to C2 are the European levels, from beginner to near native.', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                  ]),
                  _section('Skills', [_tf(_skills, 'Skills, separated by commas', field: 'skills', maxLines: 2)]),
                  _section('CV design', [
                    CvDesignPicker(
                      selected: _template,
                      accent: _accent,
                      onDesign: (id) {
                        _template = id;
                        _changed();
                      },
                      onAccent: (c) {
                        _accent = c;
                        _changed();
                      },
                    ),
                  ]),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _language,
                    decoration: InputDecoration(labelText: tr('Language of the CV')),
                    items: [for (final e in CvLabels.supported.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) {
                      _language = v ?? _language;
                      _changed();
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    key: const ValueKey('create-cv'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: _busy ? null : _create,
                    icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.pdf, size: 20),
                    label: const Text('Create CV PDF'),
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
                                FilledButton.icon(
                                  key: const ValueKey('cv-share'),
                                  onPressed: _share,
                                  icon: const Icon(AppIcons.share, size: 18),
                                  label: const Text('Share'),
                                ),
                                OutlinedButton.icon(
                                  key: const ValueKey('cv-preview'),
                                  onPressed: _preview,
                                  icon: const Icon(AppIcons.eye, size: 18),
                                  label: const Text('Preview'),
                                ),
                                OutlinedButton.icon(
                                  key: const ValueKey('cv-save'),
                                  onPressed: _saveToFiles,
                                  icon: const Icon(AppIcons.storage, size: 18),
                                  label: const Text('Save to Files'),
                                ),
                                OutlinedButton.icon(
                                  key: const ValueKey('cv-pictures'),
                                  onPressed: _asPictures,
                                  icon: const Icon(AppIcons.images, size: 18),
                                  label: const Text('Share as pictures'),
                                ),
                                OutlinedButton.icon(
                                  key: const ValueKey('cv-open'),
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
                ],
              ),
            ),
    );
  }
}
