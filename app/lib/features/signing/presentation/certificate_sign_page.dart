import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';
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
import '../../export/domain/repositories/export_repository.dart';
import '../../importer/domain/importer.dart';
import '../../reader/presentation/reader_page.dart';
import '../data/pdf_signing.dart';
import '../data/signing_service.dart';

Future<String?> _pickPdf() async {
  try {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
    return picked.isEmpty ? null : picked.first.path;
  } catch (_) {
    return null;
  }
}

Future<String?> _pickCertificate() async {
  try {
    // Certificate files have no registered type on phones, so every file can be chosen.
    final picked = await FilePicker.pickFiles();
    return picked.isEmpty ? null : picked.first.path;
  } catch (_) {
    return null;
  }
}

const _positions = {
  SignaturePosition.bottomRight: 'Bottom right',
  SignaturePosition.bottomLeft: 'Bottom left',
  SignaturePosition.bottomCenter: 'Bottom centre',
  SignaturePosition.topRight: 'Top right',
  SignaturePosition.topLeft: 'Top left',
};

/// Checks the signatures of a PDF and signs it with the person's own certificate file (.p12 or .pfx). Nothing is uploaded or stored:
/// the certificate file and its password are only held while this page is open.
class CertificateSignPage extends StatefulWidget {
  const CertificateSignPage({super.key, this.pickPdf = _pickPdf, this.pickCertificate = _pickCertificate, this.workDir = getTemporaryDirectory});
  final Future<String?> Function() pickPdf;
  final Future<String?> Function() pickCertificate;
  final Future<Directory> Function() workDir;

  @override
  State<CertificateSignPage> createState() => _CertificateSignPageState();
}

class _CertificateSignPageState extends State<CertificateSignPage> {
  final _password = TextEditingController();
  final _reason = TextEditingController();
  final _location = TextEditingController();
  String? _pdfPath;
  Uint8List? _pdf;
  CheckResult? _check;
  Uint8List? _certificate;
  String? _certificateName;
  CertificateInfo? _info;
  String? _certificateProblem;
  int _page = 0;
  bool _visible = true;
  SignaturePosition _position = SignaturePosition.bottomRight;
  bool _busy = false;
  bool _signedHere = false;

  @override
  void dispose() {
    _password.dispose();
    _reason.dispose();
    _location.dispose();
    _certificate = null;
    super.dispose();
  }

  Future<void> _choosePdf() async {
    final path = await widget.pickPdf();
    if (path == null || !mounted) return;
    setState(() => _busy = true);
    Uint8List? bytes;
    CheckResult check;
    try {
      bytes = await File(path).readAsBytes();
      check = await compute(checkPdf, bytes);
    } on Object {
      check = const CheckResult(problem: 'This PDF could not be read.');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pdfPath = path;
      _pdf = bytes;
      _check = check;
      _page = check.pages > 0 ? check.pages - 1 : 0;
      _signedHere = false;
    });
  }

  Future<void> _chooseCertificate() async {
    final path = await widget.pickCertificate();
    if (path == null || !mounted) return;
    Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on Object {
      setState(() => _certificateProblem = 'This file could not be opened.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _certificate = bytes;
      _certificateName = p.basename(path);
      _info = null;
      _certificateProblem = null;
      _password.clear();
    });
  }

  Future<void> _unlock() async {
    final file = _certificate;
    if (file == null) return;
    setState(() {
      _busy = true;
      _certificateProblem = null;
    });
    final r = await compute(unlockCertificate, UnlockRequest(file, _password.text));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _info = r.info;
      _certificateProblem = r.problem;
    });
  }

  Future<void> _sign() async {
    final pdf = _pdf;
    final cert = _certificate;
    if (pdf == null || cert == null || _info == null) return;
    setState(() => _busy = true);
    SignResult r;
    try {
      r = await compute(
        signWithCertificate,
        SignRequest(
          pdf: pdf,
          certificate: cert,
          password: _password.text,
          options: PdfSignOptions(pageIndex: _page, visible: _visible, position: _position, reason: _reason.text.trim(), location: _location.text.trim()),
        ),
      );
    } on Object {
      r = const SignResult(problem: 'The PDF could not be signed.');
    }
    if (!mounted) return;
    if (r.bytes == null) {
      setState(() => _busy = false);
      showMessage(context, r.problem ?? 'The PDF could not be signed.');
      return;
    }
    try {
      final dir = await Directory(p.join((await widget.workDir()).path, 'signed')).create(recursive: true);
      var base = p.basenameWithoutExtension(_pdfPath!);
      if (base.endsWith('_signed')) base = base.substring(0, base.length - 7);
      final file = await File(p.join(dir.path, '${base}_signed.pdf')).writeAsBytes(r.bytes!, flush: true);
      final check = await compute(checkPdf, r.bytes!);
      if (!mounted) return;
      setState(() {
        _pdfPath = file.path;
        _pdf = r.bytes;
        _check = check;
        _signedHere = true;
        _password.clear();
      });
    } on Object {
      if (mounted) showMessage(context, 'The signed PDF could not be saved. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final r = await sl<ShareService>().shareFile(path: _pdfPath!, mimeType: 'application/pdf', subject: p.basename(_pdfPath!));
    if (mounted && r.failureOrNull != null) showFailure(context, r.failureOrNull!);
  }

  Widget _card(String title, List<Widget> children) => Card(
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

  Widget _kv(String k, String v) => v.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(k, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
              ),
              Expanded(
                child: SelectableText(v, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

  (IconData, Color, String) _look(PdfSignatureReport r) => switch (r.state) {
    SignatureState.valid => (AppIcons.shield, AppColors.success, 'Signature intact. The file has not changed since it was signed.'),
    SignatureState.changedAfter => (AppIcons.info, AppColors.warning, 'Signature intact, but the file was changed after it was signed.'),
    SignatureState.altered => (AppIcons.warning, AppColors.danger, 'Altered. The signed part of the file no longer matches the signature.'),
    SignatureState.invalid => (AppIcons.warning, AppColors.danger, 'Not valid. The signature does not match its certificate.'),
    SignatureState.unsupported => (AppIcons.info, AppColors.inkMuted, 'This kind of signature cannot be checked here.'),
  };

  Widget _report(PdfSignatureReport r) {
    final (icon, color, text) = _look(r);
    final period = r.validFrom == null || r.validUntil == null ? '' : '${formatDate(r.validFrom!)} - ${formatDate(r.validUntil!)}';
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  tr(text),
                  style: TextStyle(fontWeight: FontWeight.w700, color: color, height: 1.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _kv(tr('Signed by'), r.signer ?? ''),
          _kv(tr('Issued by'), r.selfSigned ? tr('The signer (self-signed)') : (r.issuer ?? '')),
          _kv(tr('Signed on'), r.signedAt == null ? '' : formatDateTime(r.signedAt!.toLocal())),
          _kv(tr('Reason'), r.reason),
          _kv(tr('Place'), r.location),
          _kv(tr('Certificate'), period),
          _kv(tr('Method'), [r.key, r.hash].where((s) => s.isNotEmpty).join(', ')),
          if (r.certificateValidWhenSigned == false)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr('The certificate had expired, or was not yet valid, at the signing time.'),
                style: const TextStyle(color: AppColors.warning, fontSize: 13),
              ),
            ),
          if (r.problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr(r.problem!), style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
            ),
        ],
      ),
    );
  }

  Widget _signatures() {
    final check = _check!;
    if (check.problem != null) {
      return _card('Signatures in this PDF', [Text(tr(check.problem!), style: const TextStyle(height: 1.4))]);
    }
    return _card('Signatures in this PDF', [
      if (check.reports.isEmpty) Text(tr('This PDF has no signatures.'), style: const TextStyle(height: 1.4)) else for (final r in check.reports) _report(r),
      const SizedBox(height: 4),
      Text(
        tr(
          'Doculoom checks that the signature belongs to the file and that the file is unchanged. It does not check whether the signer or the certificate authority is trusted, and it does not check for revocation.',
        ),
        style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
      ),
    ]);
  }

  Widget _certificateCard() {
    final info = _info;
    return _card('Your certificate', [
      Text(
        tr('Choose the certificate file (.p12 or .pfx) and type its password. The file and the password are used on this phone only and are not kept.'),
        style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
      ),
      const SizedBox(height: AppSpacing.sm),
      OutlinedButton.icon(
        key: const ValueKey('choose-certificate'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: _busy ? null : _chooseCertificate,
        icon: const Icon(AppIcons.lock, size: 18),
        label: Text(_certificateName ?? tr('Choose certificate file')),
      ),
      if (_certificate != null) ...[
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const ValueKey('certificate-password'),
          controller: _password,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.visiblePassword,
          onChanged: (_) => setState(() => _info = null),
          onSubmitted: (_) => _busy ? null : _unlock(),
          decoration: InputDecoration(labelText: tr('Certificate password')),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          key: const ValueKey('unlock-certificate'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _busy ? null : _unlock,
          icon: const Icon(AppIcons.unlock, size: 18),
          label: const Text('Unlock'),
        ),
      ],
      if (_certificateProblem != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(tr(_certificateProblem!), style: const TextStyle(color: AppColors.danger, height: 1.4)),
        ),
      if (info != null) ...[
        const SizedBox(height: AppSpacing.sm),
        _kv(tr('Name'), info.subject),
        _kv(tr('Issued by'), info.selfSigned ? tr('The signer (self-signed)') : info.issuer),
        _kv(tr('Valid'), '${formatDate(info.validFrom)} - ${formatDate(info.validUntil)}'),
        _kv(tr('Key'), info.key),
        if (!info.validNow)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr('This certificate is not valid today (expired or not yet valid), so it cannot sign.'),
              style: const TextStyle(color: AppColors.danger, height: 1.4),
            ),
          ),
      ],
    ]);
  }

  Widget _optionsCard() {
    final pages = _check?.pages ?? 0;
    return _card('How the signature looks', [
      SwitchListTile(
        key: const ValueKey('signature-visible'),
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Show a box on the page')),
        subtitle: Text(tr('Off: the signature is in the file but nothing is drawn on a page.')),
        value: _visible,
        onChanged: (v) => setState(() => _visible = v),
      ),
      if (_visible) ...[
        Row(
          children: [
            IconButton(tooltip: tr('Previous page'), onPressed: _page > 0 ? () => setState(() => _page--) : null, icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(
                trf('Page {n} of {total}', {'n': _page + 1, 'total': pages}),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(tooltip: tr('Next page'), onPressed: _page < pages - 1 ? () => setState(() => _page++) : null, icon: const Icon(Icons.chevron_right)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<SignaturePosition>(
          key: const ValueKey('signature-position'),
          initialValue: _position,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Position')),
          items: [for (final e in _positions.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value)))],
          onChanged: (v) => setState(() => _position = v ?? _position),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      TextField(
        controller: _reason,
        maxLength: 80,
        decoration: InputDecoration(labelText: tr('Reason (optional)'), counterText: ''),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _location,
        maxLength: 80,
        decoration: InputDecoration(labelText: tr('Place (optional)'), counterText: ''),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _pdf != null && (_check?.pages ?? 0) > 0 && _check?.problem == null;
    final canSign = ready && _info != null && _info!.validNow && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign with certificate')),
      body: ListView(
        padding: contentPadding(context),
        children: [
          const Text(
            'Check who signed a PDF, or sign it with your own certificate file. The PDF, the certificate and its password stay on this phone.',
            style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            key: const ValueKey('choose-pdf'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : _choosePdf,
            icon: const Icon(AppIcons.pdf, size: 20),
            label: Text(_pdf == null ? 'Choose a PDF' : 'Choose another PDF'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_pdf != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(p.basename(_pdfPath!), style: const TextStyle(fontWeight: FontWeight.w700)),
            if ((_check?.pages ?? 0) > 0) Text(pagesLabel(_check!.pages), style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
            const SizedBox(height: AppSpacing.sm),
            _signatures(),
          ],
          if (ready) ...[
            _certificateCard(),
            if (_info != null) _optionsCard(),
            FilledButton.icon(
              key: const ValueKey('sign-pdf'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: canSign ? _sign : null,
              icon: const Icon(AppIcons.signature, size: 20),
              label: const Text('Sign the PDF'),
            ),
          ],
          if (_signedHere) ...[
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Signed. The new file:'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(p.basename(_pdfPath!)),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                          onPressed: _share,
                          icon: const Icon(AppIcons.share, size: 18),
                          label: const Text('Share'),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                          onPressed: () => context.push(
                            '/reader',
                            extra: ReaderArgs(path: _pdfPath!, kind: ImportKind.pdf),
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
              'A signature made here is a standard PDF signature (PAdES, with your certificate). Whether others accept it depends on the certificate: a certificate from a trust service gives a qualified or advanced signature, a self-made one does not. Signing does not add a trusted timestamp.',
            ),
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
