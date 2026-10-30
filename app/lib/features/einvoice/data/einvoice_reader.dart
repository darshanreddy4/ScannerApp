import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../pdf_tools/data/security/pdf_model.dart';
import '../../pdf_tools/data/security/pdf_rewriter.dart';
import '../../pdf_tools/data/security/pdf_security.dart';
import '../domain/einvoice.dart';

class EmbeddedFile {
  const EmbeddedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

String _pdfText(Uint8List b) {
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    final units = <int>[for (var i = 2; i + 1 < b.length; i += 2) (b[i] << 8) | b[i + 1]];
    return String.fromCharCodes(units);
  }
  return utf8.decode(b, allowMalformed: true);
}

/// The files attached inside a PDF (the way Factur-X and ZUGFeRD invoices carry their XML).
List<EmbeddedFile> embeddedPdfFiles(Uint8List pdf) {
  final doc = readPdfDocument(pdf);
  PdfObj? resolve(PdfObj? o) => o is PdfRef ? doc.objects[o.number] : o;
  final out = <EmbeddedFile>[];
  for (final o in doc.objects.values) {
    if (o is! PdfDict || o.nameOf('Type') != 'Filespec') continue;
    final ef = resolve(o['EF']);
    if (ef is! PdfDict) continue;
    final stream = resolve(ef['F'] ?? ef['UF']);
    if (stream is! PdfStream) continue;
    final filter = stream.dict['Filter'];
    final filters = switch (filter) {
      PdfName(:final name) => [name],
      PdfArray(:final items) => [
        for (final i in items)
          if (i is PdfName) i.name,
      ],
      _ => const <String>[],
    };
    Uint8List data;
    if (filters.isEmpty) {
      data = stream.data;
    } else if (filters.length == 1 && (filters.first == 'FlateDecode' || filters.first == 'Fl')) {
      try {
        data = Uint8List.fromList(zlib.decode(stream.data));
      } on Object {
        continue;
      }
    } else {
      continue;
    }
    final nameBytes = o.bytesOf('UF') ?? o.bytesOf('F');
    out.add(EmbeddedFile(nameBytes == null ? 'attachment' : _pdfText(nameBytes), data));
  }
  return out;
}

const _knownNames = ['factur-x.xml', 'zugferd-invoice.xml', 'xrechnung.xml', 'order-x.xml'];

class EInvoiceReadResult {
  const EInvoiceReadResult({this.invoice, this.problem, this.xmlName = ''});
  final EInvoice? invoice;

  /// Why nothing could be shown, in words for the person.
  final String? problem;

  /// The attached file the invoice was read from, when it came from a PDF.
  final String xmlName;
}

/// Reads an electronic invoice from a PDF with attached XML, or from the XML file itself.
EInvoiceReadResult readEInvoice(Uint8List bytes) {
  final isPdf = bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46;
  if (!isPdf) {
    final invoice = parseEInvoiceXml(utf8.decode(bytes, allowMalformed: true));
    return invoice == null
        ? const EInvoiceReadResult(
            problem: 'This file is not an electronic invoice that Doculoom can read. It reads Factur-X, ZUGFeRD, XRechnung, Peppol and FatturaPA.',
          )
        : EInvoiceReadResult(invoice: invoice);
  }
  final List<EmbeddedFile> files;
  try {
    files = embeddedPdfFiles(bytes);
  } on WrongPasswordException {
    return const EInvoiceReadResult(problem: 'This PDF needs a password. Unlock it first, then open it here.');
  } on PdfFormatException {
    return const EInvoiceReadResult(problem: 'This PDF could not be read.');
  }
  final xml = files.where((f) => f.name.toLowerCase().endsWith('.xml')).toList()
    ..sort((a, b) {
      int rank(EmbeddedFile f) => _knownNames.contains(f.name.toLowerCase()) ? 0 : 1;
      return rank(a).compareTo(rank(b));
    });
  for (final f in xml) {
    final invoice = parseEInvoiceXml(utf8.decode(f.bytes, allowMalformed: true));
    if (invoice != null) return EInvoiceReadResult(invoice: invoice, xmlName: f.name);
  }
  return EInvoiceReadResult(
    problem: xml.isEmpty
        ? 'This PDF has no invoice data inside. It is an ordinary PDF invoice; Doculoom shows only electronic invoices.'
        : 'The data inside this PDF is not an invoice format that Doculoom can read.',
  );
}
