import 'dart:convert';
import 'dart:typed_data';

import '../domain/slide_themes.dart';

const _nsA = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _nsP = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _nsR = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _relBase = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
const _groupHead =
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
    '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>';

/// The XML of a slide with the two usual boxes (title and content) or nothing on it.
String newSlideXml({required bool withPlaceholders}) =>
    '$_head<p:sld xmlns:a="$_nsA" xmlns:r="$_nsR" xmlns:p="$_nsP"><p:cSld><p:spTree>$_groupHead'
    '${withPlaceholders ? '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title 1"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:spPr/>'
              '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang="en-US"/></a:p></p:txBody></p:sp>'
              '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Content Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph idx="1"/></p:nvPr></p:nvSpPr><p:spPr/>'
              '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang="en-US"/></a:p></p:txBody></p:sp>' : ''}'
    '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';

/// A text box a layout offers. A null position takes the place the master gives that kind of box.
class PhSpec {
  const PhSpec(this.name, {this.type, this.idx, this.x, this.y, this.w, this.h, this.size, this.algn, this.anchor, this.bullet = true, this.prompt = 'Click to edit text'});
  final String name;
  final String? type;
  final String? idx;
  final int? x, y, w, h;
  final int? size;
  final String? algn;
  final String? anchor;
  final bool bullet;
  final String prompt;
}

/// A way to arrange a slide: where the title and the text boxes go.
class LayoutSpec {
  const LayoutSpec(this.type, this.name, this.placeholders, {this.hideMaster = false});

  /// The layout type of the file, also used to pick the layout for a new slide.
  final String type;
  final String name;
  final List<PhSpec> placeholders;
  final bool hideMaster;
}

String _band(int id, String name, int x, int y, int w, int h, {String color = 'accent1'}) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$name"/><p:cNvSpPr/><p:nvPr userDrawn="1"/></p:nvSpPr><p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:schemeClr val="$color"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>';

/// The layouts a new presentation carries. The first is the one for "Title and Content".
const deckLayouts = <LayoutSpec>[
  LayoutSpec('obj', 'Title and Content', [
    PhSpec('Title 1', type: 'title', prompt: 'Click to edit title'),
    PhSpec('Content Placeholder 2', idx: '1'),
  ]),
  LayoutSpec('blank', 'Blank', []),
  LayoutSpec('title', 'Title Slide', [
    PhSpec('Title 1', type: 'ctrTitle', x: 1524000, y: 1400000, w: 9144000, h: 2000000, size: 5400, algn: 'ctr', anchor: 'b', prompt: 'Click to edit title'),
    PhSpec('Subtitle 2', type: 'subTitle', idx: '1', x: 1524000, y: 3600000, w: 9144000, h: 1300000, size: 2800, algn: 'ctr', bullet: false),
  ], hideMaster: true),
  LayoutSpec('secHead', 'Section Header', [
    PhSpec('Title 1', type: 'title', x: 831850, y: 1709738, w: 10515600, h: 2852737, size: 5400, anchor: 'b', prompt: 'Click to edit title'),
    PhSpec('Text Placeholder 2', type: 'body', idx: '1', x: 831850, y: 4589463, w: 10515600, h: 1500187, size: 2400, bullet: false),
  ], hideMaster: true),
  LayoutSpec('twoObj', 'Two Content', [
    PhSpec('Title 1', type: 'title', prompt: 'Click to edit title'),
    PhSpec('Content Placeholder 2', idx: '1', x: 838200, y: 1825625, w: 5181600, h: 4351338),
    PhSpec('Content Placeholder 3', idx: '2', x: 6172200, y: 1825625, w: 5181600, h: 4351338),
  ]),
  LayoutSpec('titleOnly', 'Title Only', [PhSpec('Title 1', type: 'title', prompt: 'Click to edit title')]),
];

/// Shapes a layout draws behind its text: the title and section layouts carry a colour band instead of the bar at the top.
String _decor(LayoutSpec l) => switch (l.type) {
  'title' => _band(20, 'Band', 0, 5800000, 12192000, 1058000) + _band(21, 'Line', 4796000, 3500000, 2600000, 40000, color: 'accent2'),
  'secHead' => _band(20, 'Band', 0, 0, 380000, 6858000),
  _ => '',
};

String _phShape(int id, PhSpec p) {
  final ph = [if (p.type != null) 'type="${p.type}"', if (p.idx != null) 'idx="${p.idx}"'].join(' ');
  final hasPos = p.x != null && p.y != null && p.w != null && p.h != null;
  final spPr = hasPos ? '<p:spPr><a:xfrm><a:off x="${p.x}" y="${p.y}"/><a:ext cx="${p.w}" cy="${p.h}"/></a:xfrm></p:spPr>' : '<p:spPr/>';
  final lvl = (p.size != null || p.algn != null || !p.bullet)
      ? '<a:lvl1pPr${p.bullet ? '' : ' marL="0" indent="0"'}${p.algn != null ? ' algn="${p.algn}"' : ''}>${p.bullet ? '' : '<a:buNone/>'}${p.size != null ? '<a:defRPr sz="${p.size}"/>' : ''}</a:lvl1pPr>'
      : '';
  return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="${p.name}"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph $ph/></p:nvPr></p:nvSpPr>$spPr'
      '<p:txBody><a:bodyPr${p.anchor != null ? ' anchor="${p.anchor}"' : ''}><a:normAutofit/></a:bodyPr><a:lstStyle>$lvl</a:lstStyle>'
      '<a:p><a:r><a:rPr lang="en-US"/><a:t>${p.prompt}</a:t></a:r></a:p></p:txBody></p:sp>';
}

String _layout(LayoutSpec l) {
  final shapes = StringBuffer(_decor(l));
  for (var i = 0; i < l.placeholders.length; i++) {
    shapes.write(_phShape(i + 2, l.placeholders[i]));
  }
  return '$_head<p:sldLayout xmlns:a="$_nsA" xmlns:r="$_nsR" xmlns:p="$_nsP" type="${l.type}" preserve="1"${l.hideMaster ? ' showMasterSp="0"' : ''}>'
      '<p:cSld name="${l.name}"><p:spTree>$_groupHead$shapes</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>';
}

String _level(int n, int marL, int sz, {bool bullet = true}) =>
    '<a:lvl${n}pPr marL="$marL" ${bullet ? 'indent="-285750"' : 'indent="0"'} algn="l" defTabSz="914400" rtl="0" eaLnBrk="1" latinLnBrk="0" hangingPunct="1">'
    '${bullet ? '<a:spcBef><a:spcPts val="1000"/></a:spcBef><a:buClr><a:schemeClr val="accent1"/></a:buClr><a:buFont typeface="Arial"/><a:buChar char="&#8226;"/>' : '<a:buNone/>'}'
    '<a:defRPr sz="$sz" kern="1200"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mn-lt"/><a:ea typeface="+mn-ea"/><a:cs typeface="+mn-cs"/></a:defRPr></a:lvl${n}pPr>';

String _master({required bool dark}) {
  final ids = [for (var i = 0; i < deckLayouts.length; i++) '<p:sldLayoutId id="${2147483649 + i}" r:id="rId${i + 1}"/>'].join();
  final map = dark ? 'bg1="dk1" tx1="lt1" bg2="dk2" tx2="lt2"' : 'bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2"';
  return '$_head<p:sldMaster xmlns:a="$_nsA" xmlns:r="$_nsR" xmlns:p="$_nsP"><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree>$_groupHead'
      '${_band(4, 'Accent bar', 0, 0, 12192000, 120000)}'
      '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="838200" y="365125"/><a:ext cx="10515600" cy="1325563"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
      '<p:txBody><a:bodyPr vert="horz" lIns="91440" tIns="45720" rIns="91440" bIns="45720" rtlCol="0" anchor="ctr"><a:normAutofit/></a:bodyPr><a:lstStyle/><a:p><a:r><a:rPr lang="en-US"/><a:t>Click to edit Master title style</a:t></a:r></a:p></p:txBody></p:sp>'
      '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Text Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="838200" y="1825625"/><a:ext cx="10515600" cy="4351338"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
      '<p:txBody><a:bodyPr vert="horz" lIns="91440" tIns="45720" rIns="91440" bIns="45720" rtlCol="0"><a:normAutofit/></a:bodyPr><a:lstStyle/><a:p><a:pPr lvl="0"/><a:r><a:rPr lang="en-US"/><a:t>Click to edit Master text styles</a:t></a:r></a:p></p:txBody></p:sp>'
      '</p:spTree></p:cSld>'
      '<p:clrMap $map accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
      '<p:sldLayoutIdLst>$ids</p:sldLayoutIdLst>'
      '<p:txStyles><p:titleStyle><a:lvl1pPr algn="l" defTabSz="914400" rtl="0" eaLnBrk="1" latinLnBrk="0" hangingPunct="1"><a:lnSpc><a:spcPct val="90000"/></a:lnSpc><a:spcBef><a:spcPct val="0"/></a:spcBef><a:buNone/>'
      '<a:defRPr sz="4400" b="1" kern="1200"><a:solidFill><a:schemeClr val="tx2"/></a:solidFill><a:latin typeface="+mj-lt"/><a:ea typeface="+mj-ea"/><a:cs typeface="+mj-cs"/></a:defRPr></a:lvl1pPr></p:titleStyle>'
      '<p:bodyStyle>${_level(1, 228600, 2800)}${_level(2, 685800, 2400)}${_level(3, 1143000, 2000)}${_level(4, 1600200, 1800)}${_level(5, 2057400, 1800)}</p:bodyStyle>'
      '<p:otherStyle><a:defPPr><a:defRPr lang="en-US"/></a:defPPr>${_level(1, 0, 1800, bullet: false)}</p:otherStyle></p:txStyles></p:sldMaster>';
}

String _srgb(String hex) => '<a:srgbClr val="$hex"/>';

/// The theme part. In a light theme text is dark 1 and the background light 1; a dark theme swaps them and the master maps them back.
String _theme(DeckTheme t) {
  final dk1 = t.dark ? t.background : t.text, lt1 = t.dark ? t.text : t.background;
  final dk2 = t.dark ? t.soft : t.title, lt2 = t.dark ? t.title : t.soft;
  final a = t.accents;
  return '$_head<a:theme xmlns:a="$_nsA" name="${t.name}"><a:themeElements><a:clrScheme name="${t.name}">'
      '<a:dk1>${_srgb(dk1)}</a:dk1><a:lt1>${_srgb(lt1)}</a:lt1><a:dk2>${_srgb(dk2)}</a:dk2><a:lt2>${_srgb(lt2)}</a:lt2>'
      '<a:accent1>${_srgb(a[0])}</a:accent1><a:accent2>${_srgb(a[1])}</a:accent2><a:accent3>${_srgb(a[2])}</a:accent3><a:accent4>${_srgb(a[3])}</a:accent4>'
      '<a:accent5>${_srgb(a[4])}</a:accent5><a:accent6>${_srgb(a[5])}</a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme>'
      '<a:fontScheme name="Office"><a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>'
      '<a:fmtScheme name="Office"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>'
      '<a:lnStyleLst><a:ln w="6350" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/></a:ln>'
      '<a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/></a:ln>'
      '<a:ln w="19050" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/><a:miter lim="800000"/></a:ln></a:lnStyleLst>'
      '<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>'
      '<a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme>'
      '</a:themeElements></a:theme>';
}

String _rels(List<(String, String, String)> items) =>
    '$_head<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${[for (final i in items) '<Relationship Id="${i.$1}" Type="$_relBase/${i.$2}" Target="${i.$3}"/>'].join()}</Relationships>';

/// The files of a new presentation with one empty slide, [widthEmu] by [heightEmu], coloured by [theme].
Map<String, Uint8List> newPresentationFiles({double widthEmu = 12192000, double heightEmu = 6858000, DeckTheme? theme}) {
  final t = theme ?? deckThemes.first;
  final layoutOverrides = [
    for (var i = 1; i <= deckLayouts.length; i++)
      '<Override PartName="/ppt/slideLayouts/slideLayout$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>',
  ].join();
  final files = <String, String>{
    '[Content_Types].xml':
        '$_head<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
        '$layoutOverrides'
        '<Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/></Types>',
    '_rels/.rels': _rels([('rId1', 'officeDocument', 'ppt/presentation.xml')]),
    'ppt/presentation.xml':
        '$_head<p:presentation xmlns:a="$_nsA" xmlns:r="$_nsR" xmlns:p="$_nsP" saveSubsetFonts="1"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        '<p:sldIdLst><p:sldId id="256" r:id="rId2"/></p:sldIdLst><p:sldSz cx="${widthEmu.round()}" cy="${heightEmu.round()}"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>',
    'ppt/_rels/presentation.xml.rels': _rels([
      ('rId1', 'slideMaster', 'slideMasters/slideMaster1.xml'),
      ('rId2', 'slide', 'slides/slide1.xml'),
      ('rId3', 'theme', 'theme/theme1.xml'),
    ]),
    'ppt/slideMasters/slideMaster1.xml': _master(dark: t.dark),
    'ppt/slideMasters/_rels/slideMaster1.xml.rels': _rels([
      for (var i = 1; i <= deckLayouts.length; i++) ('rId$i', 'slideLayout', '../slideLayouts/slideLayout$i.xml'),
      ('rId${deckLayouts.length + 1}', 'theme', '../theme/theme1.xml'),
    ]),
    for (var i = 1; i <= deckLayouts.length; i++) ...{
      'ppt/slideLayouts/slideLayout$i.xml': _layout(deckLayouts[i - 1]),
      'ppt/slideLayouts/_rels/slideLayout$i.xml.rels': _rels([('rId1', 'slideMaster', '../slideMasters/slideMaster1.xml')]),
    },
    'ppt/slides/slide1.xml': newSlideXml(withPlaceholders: true),
    'ppt/slides/_rels/slide1.xml.rels': _rels([('rId1', 'slideLayout', '../slideLayouts/slideLayout1.xml')]),
    'ppt/theme/theme1.xml': _theme(t),
  };
  return {for (final e in files.entries) e.key: Uint8List.fromList(utf8.encode(e.value))};
}
