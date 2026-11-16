import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const docxMainNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _relNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _header = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

/// The paragraph looks a new Word file can use.
enum DocStyle {
  normal('Normal'),
  title('Title'),
  heading1('Heading1'),
  heading2('Heading2'),
  heading3('Heading3');

  const DocStyle(this.id);
  final String id;
}

enum DocList { none, bullet, number }

// ------------------------------------------------------------------ what goes into a new file

class DocRun {
  const DocRun(this.text, {this.bold = false, this.italic = false, this.color, this.sizePt});
  final String text;
  final bool bold;
  final bool italic;

  /// RGB such as 0x1F3864.
  final int? color;
  final double? sizePt;
}

sealed class DocItem {
  const DocItem();
}

class DocPara extends DocItem {
  DocPara(String text, {this.style = DocStyle.normal, this.list = DocList.none, bool bold = false, bool italic = false, this.align = 'left', int? color, double? sizePt})
    : runs = [DocRun(text, bold: bold, italic: italic, color: color, sizePt: sizePt)];
  const DocPara.runs(this.runs, {this.style = DocStyle.normal, this.list = DocList.none, this.align = 'left'});

  final List<DocRun> runs;
  final DocStyle style;
  final DocList list;

  /// left, center, right or both.
  final String align;
}

class DocTable extends DocItem {
  const DocTable(this.rows, {this.headerRow = true});
  final List<List<String>> rows;
  final bool headerRow;
}

class DocPageBreak extends DocItem {
  const DocPageBreak();
}

// ------------------------------------------------------------------ shared parts

String _esc(String s) => s
    .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _headingStyle(String id, String name, int level, int size, String color, int before, int after) =>
    '<w:style w:type="paragraph" w:styleId="$id"><w:name w:val="$name"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/>'
    '<w:uiPriority w:val="9"/><w:qFormat/>'
    '<w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="$before" w:after="$after"/><w:outlineLvl w:val="$level"/></w:pPr>'
    '<w:rPr><w:rFonts w:ascii="Calibri Light" w:hAnsi="Calibri Light"/><w:b/><w:color w:val="$color"/><w:sz w:val="$size"/><w:szCs w:val="$size"/></w:rPr></w:style>';

/// The definition of a paragraph style by its id, ready to put into a styles part.
String? docxStyleXml(String id) => switch (id) {
  'Title' =>
    '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/>'
        '<w:uiPriority w:val="10"/><w:qFormat/>'
        '<w:pPr><w:spacing w:after="120" w:line="240" w:lineRule="auto"/><w:contextualSpacing/></w:pPr>'
        '<w:rPr><w:rFonts w:ascii="Calibri Light" w:hAnsi="Calibri Light"/><w:b/><w:color w:val="1F3864"/><w:kern w:val="28"/><w:sz w:val="52"/><w:szCs w:val="52"/></w:rPr></w:style>',
  'Heading1' => _headingStyle('Heading1', 'heading 1', 0, 32, '2F5496', 320, 80),
  'Heading2' => _headingStyle('Heading2', 'heading 2', 1, 26, '2F5496', 200, 60),
  'Heading3' => _headingStyle('Heading3', 'heading 3', 2, 24, '1F3763', 160, 40),
  _ => null,
};

const _baseStyles =
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
    '<w:style w:type="character" w:default="1" w:styleId="DefaultParagraphFont"><w:name w:val="Default Paragraph Font"/><w:uiPriority w:val="1"/><w:semiHidden/><w:unhideWhenUsed/></w:style>'
    '<w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:uiPriority w:val="99"/><w:semiHidden/><w:unhideWhenUsed/>'
    '<w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>'
    '<w:style w:type="numbering" w:default="1" w:styleId="NoList"><w:name w:val="No List"/><w:uiPriority w:val="99"/><w:semiHidden/><w:unhideWhenUsed/></w:style>';

const _extraStyles =
    '<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:uiPriority w:val="34"/><w:qFormat/>'
    '<w:pPr><w:ind w:left="720"/><w:contextualSpacing/></w:pPr></w:style>'
    '<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:basedOn w:val="TableNormal"/><w:uiPriority w:val="39"/>'
    '<w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>'
    '<w:tblPr><w:tblBorders>'
    '<w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
    '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
    '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
    '</w:tblBorders></w:tblPr></w:style>';

/// A styles part with the defaults and no headings; styles are added to it when they are first used.
String emptyStylesXml() =>
    '$_header<w:styles xmlns:w="$docxMainNs"><w:docDefaults><w:rPrDefault><w:rPr>'
    '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-US" w:eastAsia="en-US" w:bidi="ar-SA"/>'
    '</w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="259" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
    '$_baseStyles</w:styles>';

String _lvl(int level, String fmt, String text, {String font = 'Calibri'}) =>
    '<w:lvl w:ilvl="$level"><w:start w:val="1"/><w:numFmt w:val="$fmt"/><w:lvlText w:val="$text"/><w:lvlJc w:val="left"/>'
    '<w:pPr><w:ind w:left="${720 * (level + 1)}" w:hanging="360"/></w:pPr>'
    '${fmt == 'bullet' ? '<w:rPr><w:rFonts w:ascii="$font" w:hAnsi="$font" w:hint="default"/></w:rPr>' : ''}</w:lvl>';

/// A bullet list or a numbered list definition with three levels.
String docxAbstractNumXml(DocList kind, int id) =>
    '<w:abstractNum w:abstractNumId="$id"><w:multiLevelType w:val="hybridMultilevel"/>'
    '${kind == DocList.bullet ? _lvl(0, 'bullet', '\u2022') + _lvl(1, 'bullet', '\u25E6') + _lvl(2, 'bullet', '\u25AA') : _lvl(0, 'decimal', '%1.') + _lvl(1, 'lowerLetter', '%2.') + _lvl(2, 'lowerRoman', '%3.')}'
    '</w:abstractNum>';

String docxNumXml(int numId, int abstractId, {bool restart = false}) =>
    '<w:num w:numId="$numId"><w:abstractNumId w:val="$abstractId"/>'
    '${restart ? '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="1"/></w:lvlOverride>' : ''}</w:num>';

String emptyNumberingXml() => '$_header<w:numbering xmlns:w="$docxMainNs"></w:numbering>';

// ------------------------------------------------------------------ writing the file

class _Body {
  final out = StringBuffer();
  var lastNumberedId = 0;
  var numberedGroups = 0;
}

String _runXml(DocRun r) {
  final props = StringBuffer();
  if (r.bold) props.write('<w:b/>');
  if (r.italic) props.write('<w:i/>');
  if (r.color != null) props.write('<w:color w:val="${(r.color! & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}"/>');
  if (r.sizePt != null) {
    final half = (r.sizePt! * 2).round();
    props.write('<w:sz w:val="$half"/><w:szCs w:val="$half"/>');
  }
  final rPr = props.isEmpty ? '' : '<w:rPr>$props</w:rPr>';
  final parts = r.text.split('\n');
  final text = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) text.write('<w:br/>');
    if (parts[i].isNotEmpty) text.write('<w:t xml:space="preserve">${_esc(parts[i])}</w:t>');
  }
  return '<w:r>$rPr$text</w:r>';
}

String _paraXml(DocPara p, _Body body) {
  final pPr = StringBuffer();
  if (p.style != DocStyle.normal) pPr.write('<w:pStyle w:val="${p.style.id}"/>');
  if (p.list == DocList.bullet) {
    pPr.write('<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>');
    body.lastNumberedId = 0;
  } else if (p.list == DocList.number) {
    if (body.lastNumberedId == 0) body.lastNumberedId = 2 + body.numberedGroups++;
    pPr.write('<w:numPr><w:ilvl w:val="0"/><w:numId w:val="${body.lastNumberedId}"/></w:numPr>');
  } else {
    body.lastNumberedId = 0;
  }
  if (p.align != 'left') pPr.write('<w:jc w:val="${p.align}"/>');
  return '<w:p>${pPr.isEmpty ? '' : '<w:pPr>$pPr</w:pPr>'}${p.runs.map(_runXml).join()}</w:p>';
}

String _tableXml(DocTable t, int width) {
  final columns = t.rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
  final w = width ~/ columns;
  final b = StringBuffer('<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="$width" w:type="dxa"/></w:tblPr><w:tblGrid>');
  for (var c = 0; c < columns; c++) {
    b.write('<w:gridCol w:w="$w"/>');
  }
  b.write('</w:tblGrid>');
  for (var r = 0; r < t.rows.length; r++) {
    final header = t.headerRow && r == 0;
    b.write('<w:tr>');
    for (var c = 0; c < columns; c++) {
      final text = c < t.rows[r].length ? t.rows[r][c] : '';
      b.write('<w:tc><w:tcPr><w:tcW w:w="$w" w:type="dxa"/>${header ? '<w:shd w:val="clear" w:color="auto" w:fill="D9E2F3"/>' : ''}</w:tcPr>');
      b.write('<w:p>${text.isEmpty && !header ? '' : _runXml(DocRun(text, bold: header))}</w:p></w:tc>');
    }
    b.write('</w:tr>');
  }
  b.write('</w:tbl>');
  return b.toString();
}

/// A new .docx made from [items]: styles for the title, three heading levels and lists are included, so the file opens in the editor and in Word.
Uint8List buildDocx(List<DocItem> items, {bool letter = false}) {
  final width = letter ? 9360 : 9026;
  final body = _Body();
  for (final item in items) {
    switch (item) {
      case DocPara():
        body.out.write(_paraXml(item, body));
      case DocTable():
        body.lastNumberedId = 0;
        body.out.write(_tableXml(item, width));
      case DocPageBreak():
        body.lastNumberedId = 0;
        body.out.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
    }
  }
  // A table cannot be the last thing in the body.
  if (items.isEmpty || items.last is! DocPara) body.out.write('<w:p/>');

  final documentXml =
      '$_header<w:document xmlns:w="$docxMainNs" xmlns:r="$_relNs"><w:body>${body.out}'
      '<w:sectPr>${letter ? '<w:pgSz w:w="12240" w:h="15840"/>' : '<w:pgSz w:w="11906" w:h="16838"/>'}'
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>'
      '</w:sectPr></w:body></w:document>';

  final styles = StringBuffer(emptyStylesXml().replaceFirst('</w:styles>', ''))
    ..write(docxStyleXml('Title'))
    ..write(docxStyleXml('Heading1'))
    ..write(docxStyleXml('Heading2'))
    ..write(docxStyleXml('Heading3'))
    ..write(_extraStyles)
    ..write('</w:styles>');

  final numbering = StringBuffer('$_header<w:numbering xmlns:w="$docxMainNs">')
    ..write(docxAbstractNumXml(DocList.bullet, 0))
    ..write(docxAbstractNumXml(DocList.number, 1))
    ..write(docxNumXml(1, 0))
    ..write(docxNumXml(2, 1));
  for (var g = 1; g < body.numberedGroups; g++) {
    numbering.write(docxNumXml(2 + g, 1, restart: true));
  }
  numbering.write('</w:numbering>');
  // The first numbered list uses numId 2 as it is; later lists restart from 1.

  const contentTypes =
      '$_header<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/></Types>';
  const rootRels =
      '$_header<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="$_relNs/officeDocument" Target="word/document.xml"/></Relationships>';
  const documentRels =
      '$_header<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="$_relNs/styles" Target="styles.xml"/>'
      '<Relationship Id="rId2" Type="$_relNs/numbering" Target="numbering.xml"/></Relationships>';

  final archive = Archive()
    ..addFile(ArchiveFile.bytes('[Content_Types].xml', utf8.encode(contentTypes)))
    ..addFile(ArchiveFile.bytes('_rels/.rels', utf8.encode(rootRels)))
    ..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(documentXml)))
    ..addFile(ArchiveFile.bytes('word/_rels/document.xml.rels', utf8.encode(documentRels)))
    ..addFile(ArchiveFile.bytes('word/styles.xml', utf8.encode(styles.toString())))
    ..addFile(ArchiveFile.bytes('word/numbering.xml', utf8.encode(numbering.toString())));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
