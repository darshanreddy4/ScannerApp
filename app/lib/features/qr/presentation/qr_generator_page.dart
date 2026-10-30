import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/di.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../domain/payments.dart';
import '../domain/qr_payloads.dart';
import '../domain/upi.dart';

enum _QrKind { text, wifi, payment, upi }

/// Groups an IBAN in fours as it is typed, in capitals, and keeps the cursor with the character it was beside.
class _IbanFormatter extends TextInputFormatter {
  const _IbanFormatter();

  static String _clean(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    final cursor = newValue.selection.end.clamp(0, text.length);
    var digits = _clean(text);
    if (digits.length > 34) digits = digits.substring(0, 34);
    final keep = _clean(text.substring(0, cursor)).length.clamp(0, digits.length);
    final out = formatIban(digits);
    var pos = 0;
    var seen = 0;
    while (pos < out.length && seen < keep) {
      if (out[pos] != ' ') seen++;
      pos++;
    }
    if (keep == digits.length) pos = out.length;
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: pos),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  const _UpperCase();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) => newValue.copyWith(text: newValue.text.toUpperCase());
}

/// Creates QR codes from text, links, Wi-Fi details or a SEPA payment entirely on the device.
class QrGeneratorPage extends StatefulWidget {
  const QrGeneratorPage({super.key, this.payment = false, this.upi = false, this.prefill});

  /// Opens on the payment (Girocode) tab.
  final bool payment;

  /// Opens on the UPI (India) tab.
  final bool upi;
  final SepaPrefill? prefill;

  @override
  State<QrGeneratorPage> createState() => _QrGeneratorPageState();
}

class _QrGeneratorPageState extends State<QrGeneratorPage> {
  late _QrKind _kind = widget.upi ? _QrKind.upi : (widget.payment ? _QrKind.payment : _QrKind.text);
  final _text = TextEditingController();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  WifiSecurity _security = WifiSecurity.wpa;
  bool _hidden = false;
  bool _showPassword = false;
  final _payName = TextEditingController();
  final _payIban = TextEditingController();
  final _payBic = TextEditingController();
  final _payAmount = TextEditingController();
  final _payRemit = TextEditingController();
  final _upiId = TextEditingController();
  final _upiName = TextEditingController();
  final _upiAmount = TextEditingController();
  final _upiNote = TextEditingController();

  final _fName = FocusNode();
  final _fIban = FocusNode();
  final _fBic = FocusNode();
  final _fAmount = FocusNode();
  final _fSsid = FocusNode();
  final _fPassword = FocusNode();
  final _fUpiId = FocusNode();
  final _fUpiName = FocusNode();
  final _fUpiAmount = FocusNode();

  /// Fields the person has been in and left: an empty required field is only called out after that.
  final _touched = <FocusNode>{};

  List<FocusNode> get _nodes => [_fName, _fIban, _fBic, _fAmount, _fSsid, _fPassword, _fUpiId, _fUpiName, _fUpiAmount];

  @override
  void initState() {
    super.initState();
    for (final n in _nodes) {
      n.addListener(() {
        if (!n.hasFocus && mounted) setState(() => _touched.add(n));
      });
    }
    final f = widget.prefill;
    if (f != null) {
      _kind = _QrKind.payment;
      _payName.text = f.name;
      _payIban.text = formatIban(f.iban);
      _payBic.text = f.bic;
      _payAmount.text = normalizeAmount(f.amount) ?? '';
      final ref = f.reference.trim();
      _payRemit.text = ref.length > 140 ? ref.substring(0, 140) : ref;
    }
  }

  @override
  void dispose() {
    for (final c in [_text, _ssid, _password, _payName, _payIban, _payBic, _payAmount, _payRemit, _upiId, _upiName, _upiAmount, _upiNote]) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  bool _was(FocusNode n) => _touched.contains(n);

  // ---- payment ----

  ({String reference, String message}) get _remit => splitRemittance(_payRemit.text);

  /// What is wrong with the payment details so far; null when the code can be made.
  String? get _paymentProblem {
    final r = _remit;
    return sepaProblem(name: _payName.text, iban: _payIban.text, bic: _payBic.text, amount: _payAmount.text, reference: r.reference, message: r.message);
  }

  String? get _payload {
    switch (_kind) {
      case _QrKind.text:
        final t = _text.text.trim();
        return t.isEmpty ? null : t;
      case _QrKind.payment:
        if (_paymentProblem != null) return null;
        final r = _remit;
        return sepaPayload(name: _payName.text, iban: _payIban.text, bic: _payBic.text, amount: _payAmount.text, reference: r.reference, message: r.message);
      case _QrKind.upi:
        if (_upiIssue != null) return null;
        return upiPayload(id: _upiId.text, name: _upiName.text, amount: _upiAmount.text, note: _upiNote.text);
      case _QrKind.wifi:
        if (QrPayloads.wifiProblem(ssid: _ssid.text, password: _password.text, security: _security) != null) return null;
        return QrPayloads.wifi(ssid: _ssid.text.trim(), password: _password.text, security: _security, hidden: _hidden);
    }
  }

  String? _nameError() => _payName.text.trim().isEmpty && _was(_fName) ? tr('Enter who is paid.') : null;

  String? _ibanError() {
    final c = checkIban(_payIban.text);
    final message = ibanProblem(_payIban.text);
    if (message == null) return null;
    final show = switch (c.status) {
      IbanStatus.empty || IbanStatus.tooShort => _was(_fIban),
      _ => true,
    };
    return show ? trf(message, ibanProblemValues(_payIban.text)) : null;
  }

  /// The line under the IBAN field: how far along it is, or which country it is from.
  ({String text, bool warning})? _ibanHelper() {
    final c = checkIban(_payIban.text);
    if (c.status == IbanStatus.valid) {
      final base = c.countryName.isEmpty ? tr('Valid IBAN') : trf('Valid IBAN from {country}', {'country': tr(c.countryName)});
      if (!c.sepa) {
        return (
          text: '$base. ${tr('This IBAN is valid, but the country is outside the SEPA area. A European banking app may not accept the code.')}',
          warning: true,
        );
      }
      return (text: base, warning: false);
    }
    if (c.status == IbanStatus.tooShort && c.expectedLength != null) {
      return (text: trf('{country}: {m} of {n} characters', {'country': tr(c.countryName), 'm': c.length, 'n': c.expectedLength!}), warning: false);
    }
    return null;
  }

  String? _bicError() {
    final t = _payBic.text.trim();
    if (t.isEmpty) return null;
    final problem = bicProblem(t);
    return problem != null && (_was(_fBic) || t.length >= 8) ? tr(problem) : null;
  }

  String? _amountError() {
    final problem = amountProblem(_payAmount.text);
    return problem != null && _was(_fAmount) ? tr(problem) : null;
  }

  void _fillExample() {
    setState(() {
      _payName.text = 'Max Mustermann';
      _payIban.text = 'DE89 3704 0044 0532 0130 00';
      _payBic.text = '';
      _payAmount.text = '12.50';
      _payRemit.text = 'Invoice 2026-001';
    });
    showMessage(context, 'Example filled in. The IBAN is a test number: do not pay it.');
  }

  // ---- UPI ----

  String? get _upiIssue => upiProblem(id: _upiId.text, name: _upiName.text, amount: _upiAmount.text, note: _upiNote.text);

  String? _upiIdError() {
    final problem = upiIdProblem(_upiId.text);
    if (problem == null) return null;
    final t = _upiId.text.trim();
    final handleTyped = t.contains('@') && t.substring(t.indexOf('@') + 1).length >= 3;
    return _was(_fUpiId) || handleTyped ? tr(problem) : null;
  }

  String? _upiAmountError() {
    final problem = upiAmountProblem(_upiAmount.text);
    return problem != null && (_was(_fUpiAmount) || problem.contains('5,00,000')) ? tr(problem) : null;
  }

  void _fillUpiExample() {
    setState(() {
      _upiId.text = 'testshop@upi';
      _upiName.text = 'Test Shop';
      _upiAmount.text = '250';
      _upiNote.text = 'Order 1042';
    });
    showMessage(context, 'Example filled in. The UPI ID is made up: do not pay it.');
  }

  // ---- share ----

  Future<void> _share(String data) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: false,
      eyeStyle: const QrEyeStyle(color: Colors.black),
      dataModuleStyle: const QrDataModuleStyle(color: Colors.black),
    );
    final bytes = await painter.toImageData(1024, format: ImageByteFormat.png);
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = await File(p.join(dir.path, 'qr_code.png')).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    final result = await sl<ShareService>().shareFile(path: file.path, mimeType: 'image/png', subject: 'QR code');
    if (mounted && result.failureOrNull != null) showFailure(context, result.failureOrNull!);
  }

  // ---- pieces ----

  Widget _gap() => const SizedBox(height: AppSpacing.sm + 4);

  Widget _card(String? title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)), const SizedBox(height: AppSpacing.sm + 2)],
          ...children,
        ],
      ),
    ),
  );

  Widget _kindChip(_QrKind kind, IconData icon, String label) => ChoiceChip(
    key: ValueKey('kind-${kind.name}'),
    selected: _kind == kind,
    showCheckmark: false,
    avatar: Icon(icon, size: 18),
    label: Text(label),
    onSelected: (_) => setState(() => _kind = kind),
  );

  Widget _paymentForm() {
    final helper = _ibanHelper();
    final ibanValid = checkIban(_payIban.text).valid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(
            'A code that European banking apps read to fill in a transfer in euros. It holds the details only; nobody is paid until the payer confirms in their bank app.',
          ),
          style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(key: const ValueKey('fill-example'), onPressed: _fillExample, child: const Text('Fill in an example')),
        ),
        _card('Who gets the money', [
          TextField(
            key: const ValueKey('pay-name'),
            controller: _payName,
            focusNode: _fName,
            maxLength: 70,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '${tr('Who is paid')} *',
              helperText: tr('The person or company that gets the money.'),
              errorText: _nameError(),
            ),
          ),
          _gap(),
          TextField(
            key: const ValueKey('pay-iban'),
            controller: _payIban,
            focusNode: _fIban,
            keyboardType: TextInputType.visiblePassword,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            inputFormatters: const [_IbanFormatter()],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'IBAN *',
              hintText: 'DE89 3704 0044 0532 0130 00',
              helperText: helper?.text,
              helperMaxLines: 4,
              helperStyle: helper?.warning == true ? const TextStyle(color: AppColors.warning) : null,
              errorText: _ibanError(),
              errorMaxLines: 4,
              suffixIcon: ibanValid ? const Icon(Icons.check_circle, color: AppColors.success) : null,
            ),
          ),
          _gap(),
          TextField(
            key: const ValueKey('pay-bic'),
            controller: _payBic,
            focusNode: _fBic,
            maxLength: 11,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')), const _UpperCase()],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr('BIC (optional)'),
              hintText: 'DEUTDEFF',
              helperText: tr('Not needed for euro payments within Europe.'),
              errorText: _bicError(),
              errorMaxLines: 3,
              counterText: '',
            ),
          ),
        ]),
        _card('Payment', [
          TextField(
            key: const ValueKey('pay-amount'),
            controller: _payAmount,
            focusNode: _fAmount,
            maxLength: 14,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]'))],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr('Amount in euros (optional)'),
              hintText: '12.50',
              prefixText: '\u20AC ',
              helperText: tr('Leave empty to let the payer type the amount.'),
              errorText: _amountError(),
              errorMaxLines: 3,
              counterText: '',
            ),
          ),
          _gap(),
          TextField(
            key: const ValueKey('pay-remit'),
            controller: _payRemit,
            maxLength: 140,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr('Reference or message (optional)'),
              helperText: tr('Invoice number or purpose. A reference that starts with RF is sent as a creditor reference.'),
              helperMaxLines: 3,
            ),
          ),
        ]),
      ],
    );
  }

  /// What still stops the code from being made, so the person is not left guessing.
  Widget _todo() {
    final nameOk = _payName.text.trim().isNotEmpty;
    final ibanOk = checkIban(_payIban.text).valid;
    final rest = _paymentProblem;
    Widget row(bool ok, String label) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: ok ? AppColors.success : AppColors.inkMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Before the code can be made:'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          row(nameOk, tr('Who is paid')),
          row(ibanOk, tr('A valid IBAN')),
          if (nameOk && ibanOk && rest != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr(rest), style: const TextStyle(color: AppColors.danger, fontSize: 13, height: 1.35)),
            ),
        ],
      ),
    );
  }

  Widget _paymentSummary() {
    final r = _remit;
    final amount = normalizeAmount(_payAmount.text);
    Widget line(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(k, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
          ),
          Expanded(
            child: SelectableText(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Column(
        children: [
          line(tr('Pay to'), _payName.text.trim()),
          line('IBAN', formatIban(_payIban.text)),
          if (_payBic.text.trim().isNotEmpty) line('BIC', _payBic.text.trim().toUpperCase()),
          line(tr('Amount'), amount == null ? tr('The payer types it') : '\u20AC $amount'),
          if (r.reference.isNotEmpty) line(tr('Reference'), r.reference),
          if (r.message.isNotEmpty) line(tr('Message'), r.message),
        ],
      ),
    );
  }

  Widget _upiForm() {
    final idWarning = upiIdWarning(_upiId.text);
    final amountWarning = upiAmountWarning(_upiAmount.text);
    final idOk = isUpiId(_upiId.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(
            'A code that UPI apps such as Google Pay, PhonePe and Paytm read to pay you. The payer confirms with their own UPI PIN; nobody is paid until then.',
          ),
          style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(key: const ValueKey('fill-upi-example'), onPressed: _fillUpiExample, child: const Text('Fill in an example')),
        ),
        _card('Who gets the money', [
          TextField(
            key: const ValueKey('upi-id'),
            controller: _upiId,
            focusNode: _fUpiId,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '${tr('UPI ID')} *',
              hintText: 'name@okaxis',
              helperText: idWarning == null ? tr('Find it in your UPI app, under your profile or QR code.') : tr(idWarning),
              helperMaxLines: 3,
              helperStyle: idWarning == null ? null : const TextStyle(color: AppColors.warning),
              errorText: _upiIdError(),
              errorMaxLines: 3,
              suffixIcon: idOk ? const Icon(Icons.check_circle, color: AppColors.success) : null,
            ),
          ),
          _gap(),
          TextField(
            key: const ValueKey('upi-name'),
            controller: _upiName,
            focusNode: _fUpiName,
            maxLength: upiMaxName,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '${tr('Who is paid')} *',
              helperText: tr('The name the payer sees before they pay.'),
              errorText: _upiName.text.trim().isEmpty && _was(_fUpiName) ? tr('Enter who is paid.') : null,
            ),
          ),
        ]),
        _card('Payment', [
          TextField(
            key: const ValueKey('upi-amount'),
            controller: _upiAmount,
            focusNode: _fUpiAmount,
            maxLength: 12,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr('Amount in rupees (optional)'),
              hintText: '250',
              prefixText: '\u20B9 ',
              helperText: amountWarning == null ? tr('Leave empty to let the payer type the amount.') : tr(amountWarning),
              helperMaxLines: 3,
              helperStyle: amountWarning == null ? null : const TextStyle(color: AppColors.warning),
              errorText: _upiAmountError(),
              errorMaxLines: 3,
              counterText: '',
            ),
          ),
          _gap(),
          TextField(
            key: const ValueKey('upi-note'),
            controller: _upiNote,
            maxLength: upiMaxNote,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr('Note (optional)'), helperText: tr('Shown to the payer, for example an order or invoice number.')),
          ),
        ]),
      ],
    );
  }

  Widget _upiTodo() {
    final idOk = isUpiId(_upiId.text);
    final nameOk = _upiName.text.trim().isNotEmpty;
    final rest = idOk && nameOk ? _upiIssue : null;
    Widget row(bool ok, String label) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: ok ? AppColors.success : AppColors.inkMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Before the code can be made:'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          row(idOk, tr('A valid UPI ID')),
          row(nameOk, tr('Who is paid')),
          if (rest != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr(rest), style: const TextStyle(color: AppColors.danger, fontSize: 13, height: 1.35)),
            ),
        ],
      ),
    );
  }

  Widget _upiSummary() {
    final amount = normalizeAmount(_upiAmount.text);
    Widget line(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(k, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
          ),
          Expanded(
            child: SelectableText(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Column(
        children: [
          line(tr('Pay to'), _upiName.text.trim()),
          line(tr('UPI ID'), _upiId.text.trim()),
          line(tr('Amount'), amount == null ? tr('The payer types it') : '\u20B9 $amount'),
          if (_upiNote.text.trim().isNotEmpty) line(tr('Note'), _upiNote.text.trim()),
        ],
      ),
    );
  }

  Widget _wifiForm() {
    final problem = QrPayloads.wifiProblem(ssid: _ssid.text, password: _password.text, security: _security);
    final ssidError = _ssid.text.trim().isEmpty
        ? (_was(_fSsid) ? tr('Enter the network name.') : null)
        : (problem != null && problem.contains('network name') ? tr(problem) : null);
    final passwordError = _password.text.isEmpty
        ? (_was(_fPassword) && _ssid.text.trim().isNotEmpty ? tr('Enter the password, or choose None for an open network.') : null)
        : (problem != null && problem.contains('password') ? tr(problem) : null);
    return _card(null, [
      TextField(
        controller: _ssid,
        focusNode: _fSsid,
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: '${tr('Network name (SSID)')} *', errorText: ssidError, errorMaxLines: 3),
      ),
      _gap(),
      DropdownButtonFormField<WifiSecurity>(
        initialValue: _security,
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Security')),
        items: [for (final s in WifiSecurity.values) DropdownMenuItem(value: s, child: Text(s.label))],
        onChanged: (s) => setState(() => _security = s ?? _security),
      ),
      if (_security != WifiSecurity.open) ...[
        _gap(),
        TextField(
          controller: _password,
          focusNode: _fPassword,
          obscureText: !_showPassword,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '${tr('Password')} *',
            helperText: tr(
              _security == WifiSecurity.wpa
                  ? 'A WPA password has 8 to 63 characters.'
                  : 'A WEP password has 5 or 13 characters, or 10 or 26 hexadecimal digits.',
            ),
            helperMaxLines: 3,
            errorText: passwordError,
            errorMaxLines: 3,
            suffixIcon: IconButton(
              icon: Icon(_showPassword ? AppIcons.eyeOff : AppIcons.eye, size: 18),
              tooltip: tr(_showPassword ? 'Hide password' : 'Show password'),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
        ),
      ],
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Hidden network'), value: _hidden, onChanged: (v) => setState(() => _hidden = v)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    final tooLong = payload != null && _kind != _QrKind.payment && payload.length > QrPayloads.maxChars;

    return Scaffold(
      appBar: AppBar(title: const Text('QR code generator')),
      body: SingleChildScrollView(
        padding: contentPadding(context),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                _kindChip(_QrKind.text, AppIcons.link, tr('Text or link')),
                _kindChip(_QrKind.wifi, AppIcons.wifi, 'Wi-Fi'),
                _kindChip(_QrKind.payment, AppIcons.receipt, tr('SEPA payment')),
                _kindChip(_QrKind.upi, AppIcons.receipt, tr('UPI payment')),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (_kind == _QrKind.text)
              TextField(
                controller: _text,
                minLines: 3,
                maxLines: 6,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: tr('Text or link'),
                  helperText: '${_text.text.length}/${QrPayloads.maxChars} characters',
                  alignLabelWithHint: true,
                ),
              )
            else if (_kind == _QrKind.payment)
              _paymentForm()
            else if (_kind == _QrKind.upi)
              _upiForm()
            else
              _wifiForm(),
            const SizedBox(height: AppSpacing.sm),
            if (payload == null)
              (_kind == _QrKind.payment
                  ? _todo()
                  : _kind == _QrKind.upi
                  ? _upiTodo()
                  : const Center(
                      child: Text('Enter details to create a QR code', style: TextStyle(color: AppColors.inkMuted)),
                    ))
            else if (tooLong)
              const Center(
                child: Text('Too long for a QR code. Shorten it or use a link instead.', style: TextStyle(color: AppColors.danger)),
              )
            else ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: QrImageView(
                    key: ValueKey(payload),
                    data: payload,
                    size: 240,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
              ),
              if (_kind == _QrKind.upi) ...[
                const SizedBox(height: AppSpacing.md),
                _upiSummary(),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  tr('Check it by scanning it with your UPI app before you share it.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.35),
                ),
              ],
              if (_kind == _QrKind.payment) ...[
                const SizedBox(height: AppSpacing.md),
                _paymentSummary(),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  tr('Check it by scanning it with your banking app before you share it.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.35),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => _share(payload),
                icon: const Icon(AppIcons.share, size: 20),
                label: const Text('Share QR image'),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
