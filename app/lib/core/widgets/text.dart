import 'package:flutter/material.dart' as m;

import '../i18n/tr.dart';

/// The ordinary [m.Text], except that fixed text is shown in the chosen language when it has a translation. Files use it by hiding the
/// framework's `Text` from their imports; every use of `Text('...')` then follows the language, and the widget is still a framework
/// [m.Text] for anything that looks for one.
class Text extends m.Text {
  const Text(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  });

  const Text.rich(
    super.textSpan, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  }) : super.rich();

  @override
  m.Widget build(m.BuildContext context) {
    // Depending on the locale makes this text draw again when the language is changed.
    m.Localizations.maybeLocaleOf(context);
    final english = data;
    if (english == null || Strings.isEnglish) return super.build(context);
    final shown = tr(english);
    if (shown == english) return super.build(context);
    return m.Text(
      shown,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
