import 'dart:typed_data';

import 'pdf_signing.dart';
import 'pkcs12.dart';

/// What the person sees of a certificate after unlocking it. The key itself never leaves the signing step.
class CertificateInfo {
  const CertificateInfo({
    required this.subject,
    required this.issuer,
    required this.validFrom,
    required this.validUntil,
    required this.selfSigned,
    required this.key,
    required this.validNow,
  });
  final String subject;
  final String issuer;
  final DateTime validFrom;
  final DateTime validUntil;
  final bool selfSigned;
  final String key;
  final bool validNow;
}

class UnlockResult {
  const UnlockResult({this.info, this.problem, this.wrongPassword = false});
  final CertificateInfo? info;
  final String? problem;
  final bool wrongPassword;
}

class UnlockRequest {
  const UnlockRequest(this.file, this.password);
  final Uint8List file;
  final String password;
}

/// Opens a .p12/.pfx file with its password and describes the certificate inside. Runs well in an isolate.
UnlockResult unlockCertificate(UnlockRequest r) {
  try {
    final cred = readPkcs12(r.file, r.password);
    final c = cred.certificate;
    return UnlockResult(
      info: CertificateInfo(
        subject: c.subject.display,
        issuer: c.issuer.display,
        validFrom: c.notBefore,
        validUntil: c.notAfter,
        selfSigned: c.selfSigned,
        key: c.publicKey.description,
        validNow: c.validAt(DateTime.now()),
      ),
    );
  } on WrongCertificatePasswordException {
    return const UnlockResult(problem: 'The password is not right.', wrongPassword: true);
  } on Pkcs12Exception catch (e) {
    return UnlockResult(problem: e.message);
  } on Object {
    return const UnlockResult(problem: 'This file is not a certificate file Doculoom can read.');
  }
}

class SignRequest {
  const SignRequest({required this.pdf, required this.certificate, required this.password, required this.options});
  final Uint8List pdf;
  final Uint8List certificate;
  final String password;
  final PdfSignOptions options;
}

class SignResult {
  const SignResult({this.bytes, this.problem});
  final Uint8List? bytes;
  final String? problem;
}

/// Signs the PDF with the certificate file. Runs well in an isolate.
SignResult signWithCertificate(SignRequest r) {
  try {
    final cred = readPkcs12(r.certificate, r.password);
    if (!cred.certificate.validAt(DateTime.now())) {
      return const SignResult(problem: 'This certificate is not valid today (expired or not yet valid), so it cannot sign.');
    }
    return SignResult(bytes: signPdf(r.pdf, cred, options: r.options));
  } on SigningException catch (e) {
    return SignResult(problem: e.message);
  } on Pkcs12Exception catch (e) {
    return SignResult(problem: e.message);
  } on Object {
    return const SignResult(problem: 'The PDF could not be signed.');
  }
}

class CheckResult {
  const CheckResult({this.reports = const [], this.pages = 0, this.problem});
  final List<PdfSignatureReport> reports;
  final int pages;
  final String? problem;
}

/// Reads the signatures of a PDF and counts its pages. Runs well in an isolate.
CheckResult checkPdf(Uint8List pdf) {
  try {
    return CheckResult(reports: checkPdfSignatures(pdf), pages: pdfPageCount(pdf));
  } on SigningException catch (e) {
    return CheckResult(problem: e.message);
  } on Object {
    return const CheckResult(problem: 'This PDF could not be read.');
  }
}
