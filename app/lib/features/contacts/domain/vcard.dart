import 'dart:convert';

import 'contact_parser.dart';

String _escape(String v) =>
    v.replaceAll('\\', '\\\\').replaceAll(';', r'\;').replaceAll(',', r'\,').replaceAll('\r\n', r'\n').replaceAll('\n', r'\n').replaceAll('\r', r'\n');

/// Cuts a line into pieces of at most 75 bytes, never inside a character, continued with a leading space.
List<String> _fold(String line) {
  final out = <String>[];
  var current = StringBuffer();
  var bytes = 0;
  var limit = 75;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final size = utf8.encode(ch).length;
    if (bytes + size > limit) {
      out.add(current.toString());
      current = StringBuffer(' ');
      bytes = 1;
      limit = 75;
    }
    current.write(ch);
    bytes += size;
  }
  out.add(current.toString());
  return out;
}

/// A vCard 3.0 for [c], the format every phone's Contacts app opens. Empty parts are left out.
String buildVCard(ContactDraft c) {
  final lines = <String>['BEGIN:VCARD', 'VERSION:3.0'];
  final name = c.name.trim();
  if (name.isNotEmpty) {
    final parts = name.split(RegExp(r'\s+'));
    final family = parts.length > 1 ? parts.last : '';
    final given = parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : parts.first;
    lines.add('N:${_escape(family)};${_escape(given)};;;');
    lines.add('FN:${_escape(name)}');
  } else {
    // A card must have a name; the first number or address stands in for it.
    final stand = [...c.emails, ...c.phones, c.organization].firstWhere((s) => s.trim().isNotEmpty, orElse: () => 'Contact');
    lines.add('N:;${_escape(stand)};;;');
    lines.add('FN:${_escape(stand)}');
  }
  if (c.organization.trim().isNotEmpty) lines.add('ORG:${_escape(c.organization.trim())}');
  if (c.title.trim().isNotEmpty) lines.add('TITLE:${_escape(c.title.trim())}');
  for (final p in c.phones) {
    if (p.trim().isNotEmpty) lines.add('TEL;TYPE=VOICE:${_escape(p.trim())}');
  }
  for (final e in c.emails) {
    if (e.trim().isNotEmpty) lines.add('EMAIL;TYPE=INTERNET:${_escape(e.trim())}');
  }
  for (final w in c.websites) {
    if (w.trim().isNotEmpty) lines.add('URL:${_escape(w.trim())}');
  }
  if (c.address.trim().isNotEmpty) lines.add('ADR;TYPE=WORK:;;${_escape(c.address.trim())};;;;');
  lines.add('END:VCARD');
  return '${[for (final l in lines) ..._fold(l)].join('\r\n')}\r\n';
}
