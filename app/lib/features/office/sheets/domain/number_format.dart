import 'dart:math' as math;

/// Shows a number the way a spreadsheet does for a given format code, such as 0.00, #,##0, 0%, dd/mm/yyyy or "$"#,##0.00.
abstract final class NumberFormatter {
  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  static const _days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  /// Formats built into Excel files, by number.
  static const builtIn = <int, String>{
    0: 'General',
    1: '0',
    2: '0.00',
    3: '#,##0',
    4: '#,##0.00',
    9: '0%',
    10: '0.00%',
    11: '0.00E+00',
    12: '# ?/?',
    13: '# ??/??',
    14: 'mm-dd-yy',
    15: 'd-mmm-yy',
    16: 'd-mmm',
    17: 'mmm-yy',
    18: 'h:mm AM/PM',
    19: 'h:mm:ss AM/PM',
    20: 'h:mm',
    21: 'h:mm:ss',
    22: 'm/d/yy h:mm',
    37: '#,##0 ;(#,##0)',
    38: '#,##0 ;[Red](#,##0)',
    39: '#,##0.00;(#,##0.00)',
    40: '#,##0.00;[Red](#,##0.00)',
    45: 'mm:ss',
    46: '[h]:mm:ss',
    47: 'mmss.0',
    49: '@',
  };

  /// True when the code shows a date or time.
  static bool isDate(String code) {
    if (code == 'General') return false;
    final first = _section(code, 0);
    if (RegExp(r'\[(h+|m+|s+)\]', caseSensitive: false).hasMatch(first)) return true;
    final s = _strip(first);
    return RegExp(r'[ymdhs]', caseSensitive: false).hasMatch(s) && !RegExp(r'^[#0?,.%\s]*$').hasMatch(s) || s.toUpperCase().contains('AM/PM');
  }

  /// A cell value turned into text. [date1904] is the workbook's date system.
  static String format(double value, String code, {bool date1904 = false}) {
    if (code == 'General' || code.isEmpty) return general(value);
    final sections = _split(code);
    var section = sections.first;
    var v = value;
    if (sections.length >= 2 && value < 0) {
      section = sections[1];
      v = -value;
    } else if (sections.length >= 3 && value == 0) {
      section = sections[2];
    } else if (value < 0 && sections.length == 1) {
      v = -value;
      final shown = _formatSection(section, v, date1904);
      return '-$shown';
    }
    return _formatSection(section, v, date1904);
  }

  static String general(double v) {
    if (v.isNaN || v.isInfinite) return '#NUM!';
    if (v == v.roundToDouble() && v.abs() < 1e11) return v.toInt().toString();
    final abs = v.abs();
    if (abs >= 1e11 || (abs < 1e-9 && abs > 0)) {
      final parts = v.toStringAsExponential(5).split('e');
      var mantissa = parts[0];
      if (mantissa.contains('.')) mantissa = mantissa.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      final exp = int.parse(parts[1]);
      return '${mantissa}E${exp < 0 ? '-' : '+'}${exp.abs().toString().padLeft(2, '0')}';
    }
    var s = v.toStringAsPrecision(10);
    if (s.contains('e')) s = v.toString();
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  static String _section(String code, int i) {
    final parts = _split(code);
    return i < parts.length ? parts[i] : parts.first;
  }

  static List<String> _split(String code) {
    final out = <String>[];
    final cur = StringBuffer();
    var inQuote = false, inBracket = false;
    for (var i = 0; i < code.length; i++) {
      final c = code[i];
      if (c == '\\' && i + 1 < code.length) {
        cur.write(c);
        cur.write(code[++i]);
        continue;
      }
      if (c == '"') inQuote = !inQuote;
      if (!inQuote) {
        if (c == '[') inBracket = true;
        if (c == ']') inBracket = false;
      }
      if (c == ';' && !inQuote && !inBracket) {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(c);
      }
    }
    out.add(cur.toString());
    return out;
  }

  /// Removes quotes, brackets and escapes so that only format letters remain.
  static String _strip(String s) {
    final out = StringBuffer();
    var inQuote = false, inBracket = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '\\') {
        i++;
        continue;
      }
      if (c == '"') {
        inQuote = !inQuote;
        continue;
      }
      if (inQuote) continue;
      if (c == '[') {
        inBracket = true;
        continue;
      }
      if (c == ']') {
        inBracket = false;
        continue;
      }
      if (inBracket) continue;
      out.write(c);
    }
    return out.toString();
  }

  static String _formatSection(String section, double v, bool date1904) {
    if (section.trim() == '@') return general(v);
    if (isDate(section)) return _formatDate(section, v, date1904);
    return _formatNumber(section, v);
  }

  // region numbers

  static String _formatNumber(String section, double v) {
    // Tokens: digit placeholders, separators and literal text.
    final tokens = <_Tok>[];
    var i = 0;
    while (i < section.length) {
      final c = section[i];
      if (c == '"') {
        final end = section.indexOf('"', i + 1);
        final text = section.substring(i + 1, end < 0 ? section.length : end);
        tokens.add(_Tok.lit(text));
        i = end < 0 ? section.length : end + 1;
      } else if (c == '\\' && i + 1 < section.length) {
        tokens.add(_Tok.lit(section[i + 1]));
        i += 2;
      } else if (c == '[') {
        final end = section.indexOf(']', i);
        final inner = section.substring(i + 1, end < 0 ? section.length : end);
        if (inner.startsWith(r'$')) {
          final symbol = inner.substring(1).split('-').first;
          if (symbol.isNotEmpty) tokens.add(_Tok.lit(symbol));
        }
        i = end < 0 ? section.length : end + 1;
      } else if (c == '_' && i + 1 < section.length) {
        tokens.add(_Tok.lit(' '));
        i += 2;
      } else if (c == '*' && i + 1 < section.length) {
        i += 2;
      } else if ('0#?'.contains(c)) {
        tokens.add(_Tok.digit(c));
        i++;
      } else if (c == '.') {
        tokens.add(_Tok.point());
        i++;
      } else if (c == ',') {
        tokens.add(_Tok.comma());
        i++;
      } else if (c == '%') {
        tokens.add(_Tok.percent());
        i++;
      } else if ((c == 'E' || c == 'e') && i + 1 < section.length && (section[i + 1] == '+' || section[i + 1] == '-')) {
        tokens.add(_Tok.exp(section[i + 1] == '+'));
        i += 2;
      } else {
        tokens.add(_Tok.lit(c));
        i++;
      }
    }

    var scaled = v;
    if (tokens.any((t) => t.kind == _K.percent)) scaled *= 100;
    // A comma right after the last digit placeholder divides by a thousand each.
    final lastDigit = tokens.lastIndexWhere((t) => t.kind == _K.digit);
    var trailingCommas = 0;
    if (lastDigit >= 0) {
      for (var k = lastDigit + 1; k < tokens.length && tokens[k].kind == _K.comma; k++) {
        trailingCommas++;
      }
    }
    for (var k = 0; k < trailingCommas; k++) {
      scaled /= 1000;
    }
    final firstDigit = tokens.indexWhere((t) => t.kind == _K.digit);
    final thousands =
        firstDigit >= 0 &&
        tokens.indexWhere((t) => t.kind == _K.comma, firstDigit) >= 0 &&
        tokens.indexWhere((t) => t.kind == _K.comma, firstDigit) < lastDigit;

    final pointAt = tokens.indexWhere((t) => t.kind == _K.point);
    final expAt = tokens.indexWhere((t) => t.kind == _K.exp);
    final intSlots = [
      for (var k = 0; k < tokens.length; k++)
        if (tokens[k].kind == _K.digit && (pointAt < 0 || k < pointAt) && (expAt < 0 || k < expAt)) tokens[k].ch,
    ];
    final fracSlots = [
      for (var k = 0; k < tokens.length; k++)
        if (tokens[k].kind == _K.digit && pointAt >= 0 && k > pointAt && (expAt < 0 || k < expAt)) tokens[k].ch,
    ];

    if (expAt >= 0) return _scientific(tokens, scaled, intSlots.length, fracSlots.length, expAt);

    final decimals = fracSlots.length;
    final factor = math.pow(10, decimals).toDouble();
    final rounded = (scaled * factor).roundToDouble() / factor;
    final fixed = rounded.toStringAsFixed(decimals);
    var intPart = fixed.contains('.') ? fixed.substring(0, fixed.indexOf('.')) : fixed;
    var fracPart = fixed.contains('.') ? fixed.substring(fixed.indexOf('.') + 1) : '';
    if (intPart == '0' && !intSlots.contains('0')) intPart = '';
    // Trailing optional fraction digits (#) are dropped when zero.
    final fracOut = StringBuffer();
    for (var k = 0; k < fracSlots.length; k++) {
      final d = k < fracPart.length ? fracPart[k] : '0';
      final isLastRun = fracPart.substring(k).replaceAll('0', '').isEmpty;
      if (fracSlots[k] == '0') {
        fracOut.write(d);
      } else if (fracSlots[k] == '?') {
        fracOut.write(isLastRun && d == '0' ? ' ' : d);
      } else if (!(isLastRun && d == '0')) {
        fracOut.write(d);
      }
    }
    fracPart = fracOut.toString();

    // Digit placeholders fill the integer part from the right; extra digits go to the front.
    final required = intSlots.where((s) => s == '0').length;
    while (intPart.length < required) {
      intPart = '0$intPart';
    }
    final spaces = intSlots.where((s) => s == '?').length;
    while (intPart.length < required + spaces && intSlots.contains('?')) {
      intPart = ' $intPart';
    }
    if (thousands) intPart = _group(intPart);

    final out = StringBuffer();
    var intPlaced = false, fracPlaced = false;
    for (var k = 0; k < tokens.length; k++) {
      final t = tokens[k];
      switch (t.kind) {
        case _K.lit:
          out.write(t.ch);
        case _K.percent:
          out.write('%');
        case _K.digit:
          if (pointAt >= 0 && k > pointAt) {
            if (!fracPlaced) {
              out.write(fracPart);
              fracPlaced = true;
            }
          } else if (!intPlaced) {
            out.write(intPart);
            intPlaced = true;
          }
        case _K.point:
          if (fracPart.isNotEmpty) out.write('.');
        case _K.comma:
        case _K.exp:
          break;
      }
    }
    return out.toString();
  }

  static String _group(String digits) {
    final neg = digits.startsWith('-');
    final body = neg ? digits.substring(1) : digits;
    final out = StringBuffer();
    for (var k = 0; k < body.length; k++) {
      if (k > 0 && (body.length - k) % 3 == 0 && body[k - 1] != ' ') out.write(',');
      out.write(body[k]);
    }
    return neg ? '-$out' : out.toString();
  }

  static String _scientific(List<_Tok> tokens, double v, int intDigits, int fracDigits, int expAt) {
    if (v == 0) return '${'0'.padLeft(math.max(1, intDigits), '0')}${fracDigits > 0 ? '.${'0' * fracDigits}' : ''}E+00';
    var exp = (math.log(v.abs()) / math.ln10).floor();
    var mant = v / math.pow(10, exp);
    final f = math.pow(10, fracDigits).toDouble();
    mant = (mant * f).roundToDouble() / f;
    if (mant.abs() >= 10) {
      mant /= 10;
      exp++;
    }
    final sign = exp < 0 ? '-' : (tokens[expAt].plus ? '+' : '');
    return '${mant.toStringAsFixed(fracDigits)}E$sign${exp.abs().toString().padLeft(2, '0')}';
  }

  // endregion

  // region dates

  static DateTime serialToDate(double serial, {bool date1904 = false}) {
    final days = serial.floor();
    final fraction = serial - days;
    DateTime base;
    int offset;
    if (date1904) {
      base = DateTime.utc(1904);
      offset = days;
    } else {
      // Excel counts a 29 February 1900 that never existed; serial 60 is that day.
      base = DateTime.utc(1899, 12, 30);
      offset = days < 60 ? days + 1 : days;
    }
    final ms = (fraction * 86400000).round();
    return base.add(Duration(days: offset, milliseconds: ms));
  }

  static double dateToSerial(DateTime d, {bool date1904 = false}) {
    final utc = DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond);
    final base = date1904 ? DateTime.utc(1904) : DateTime.utc(1899, 12, 30);
    final days = utc.difference(base).inMilliseconds / 86400000;
    return !date1904 && days < 60 ? days - 1 : days;
  }

  static String _formatDate(String section, double v, bool date1904) {
    final elapsed = RegExp(r'\[(h+|m+|s+)\]', caseSensitive: false).firstMatch(section);
    final d = serialToDate(v, date1904: date1904);
    final twelve = section.toUpperCase().contains('AM/PM') || section.toUpperCase().contains('A/P');
    final out = StringBuffer();
    var i = 0;
    String? last; // last time or date token, to tell month from minute
    final stripped = section;
    while (i < stripped.length) {
      final c = stripped[i];
      final lower = c.toLowerCase();
      if (c == '"') {
        final end = stripped.indexOf('"', i + 1);
        out.write(stripped.substring(i + 1, end < 0 ? stripped.length : end));
        i = end < 0 ? stripped.length : end + 1;
        continue;
      }
      if (c == '\\' && i + 1 < stripped.length) {
        out.write(stripped[i + 1]);
        i += 2;
        continue;
      }
      if (c == '[') {
        final end = stripped.indexOf(']', i);
        final inner = stripped.substring(i + 1, end < 0 ? stripped.length : end).toLowerCase();
        if (elapsed != null && RegExp(r'^(h+|m+|s+)$').hasMatch(inner)) {
          final totalSeconds = (v * 86400).round();
          final n = switch (inner[0]) {
            'h' => totalSeconds ~/ 3600,
            'm' => totalSeconds ~/ 60,
            _ => totalSeconds,
          };
          out.write(n.toString().padLeft(inner.length, '0'));
        } else if (inner.startsWith(r'$')) {
          out.write(inner.substring(1).split('-').first);
        }
        i = end < 0 ? stripped.length : end + 1;
        continue;
      }
      if (stripped.substring(i).toUpperCase().startsWith('AM/PM')) {
        out.write(d.hour >= 12 ? 'PM' : 'AM');
        i += 5;
        continue;
      }
      if (stripped.substring(i).toUpperCase().startsWith('A/P')) {
        out.write(d.hour >= 12 ? 'P' : 'A');
        i += 3;
        continue;
      }
      if ('ymdhs'.contains(lower)) {
        var n = 1;
        while (i + n < stripped.length && stripped[i + n].toLowerCase() == lower) {
          n++;
        }
        i += n;
        switch (lower) {
          case 'y':
            out.write(n <= 2 ? (d.year % 100).toString().padLeft(2, '0') : d.year.toString().padLeft(4, '0'));
            last = 'y';
          case 'd':
            out.write(
              n == 1 ? '${d.day}' : (n == 2 ? d.day.toString().padLeft(2, '0') : (n == 3 ? _days[d.weekday % 7].substring(0, 3) : _days[d.weekday % 7])),
            );
            last = 'd';
          case 'h':
            final h = twelve ? (d.hour % 12 == 0 ? 12 : d.hour % 12) : d.hour;
            out.write(n == 1 ? '$h' : h.toString().padLeft(2, '0'));
            last = 'h';
          case 's':
            out.write(n == 1 ? '${d.second}' : d.second.toString().padLeft(2, '0'));
            last = 's';
          case 'm':
            // "m" after an hour or before a second means minutes, otherwise it is the month.
            final rest = stripped.substring(i).toLowerCase();
            final minutes = last == 'h' || RegExp(r'^[^ymdh]*s').hasMatch(rest.replaceAll(RegExp(r'"[^"]*"'), ''));
            if (minutes && n <= 2) {
              out.write(n == 1 ? '${d.minute}' : d.minute.toString().padLeft(2, '0'));
              last = 'min';
            } else {
              final name = _months[d.month - 1];
              out.write(
                n == 1
                    ? '${d.month}'
                    : (n == 2 ? d.month.toString().padLeft(2, '0') : (n == 3 ? name.substring(0, 3) : (n == 4 ? name : name.substring(0, 1)))),
              );
              last = 'M';
            }
        }
        continue;
      }
      if (c == '.' && i + 1 < stripped.length && stripped[i + 1] == '0') {
        var n = 0;
        while (i + 1 + n < stripped.length && stripped[i + 1 + n] == '0') {
          n++;
        }
        out.write('.${d.millisecond.toString().padLeft(3, '0').substring(0, n.clamp(1, 3))}');
        i += 1 + n;
        continue;
      }
      if (c == '_' || c == '*') {
        i += 2;
        continue;
      }
      out.write(c);
      i++;
    }
    return out.toString();
  }

  // endregion
}

enum _K { digit, point, comma, percent, exp, lit }

class _Tok {
  _Tok(this.kind, this.ch, this.plus);
  _Tok.lit(String c) : this(_K.lit, c, true);
  _Tok.digit(String c) : this(_K.digit, c, true);
  _Tok.point() : this(_K.point, '.', true);
  _Tok.comma() : this(_K.comma, ',', true);
  _Tok.percent() : this(_K.percent, '%', true);
  _Tok.exp(bool plus) : this(_K.exp, 'E', plus);
  final _K kind;
  final String ch;
  final bool plus;
}
