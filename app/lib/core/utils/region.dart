import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show ValueNotifier;

/// Paper for pages the app lays out itself and for what it prints.
enum PaperChoice {
  auto('Automatic (by region)'),
  a4('A4'),
  letter('US Letter');

  const PaperChoice(this.label);
  final String label;
}

/// How dates are written.
enum DateStyle {
  auto('Automatic (by region)'),
  dayFirst('Day first: 5 Mar 2026'),
  monthFirst('Month first: Mar 5, 2026'),
  yearFirst('Year first: 2026-03-05');

  const DateStyle(this.label);
  final String label;
}

/// Which country-specific tools come first on the Tools page.
enum ToolRegion {
  auto('Automatic (by country)'),
  india('India'),
  usa('United States'),
  europe('Europe and UK'),
  gulf('Gulf countries'),
  other('Other countries');

  const ToolRegion(this.label);
  final String label;
}

const _europeCountries = {
  'AT',
  'BE',
  'BG',
  'HR',
  'CY',
  'CZ',
  'DK',
  'EE',
  'FI',
  'FR',
  'DE',
  'GR',
  'HU',
  'IE',
  'IT',
  'LV',
  'LT',
  'LU',
  'MT',
  'NL',
  'PL',
  'PT',
  'RO',
  'SK',
  'SI',
  'ES',
  'SE', //
  'GB', 'CH', 'NO', 'IS', 'LI', 'AD', 'MC', 'SM', 'VA', 'AL', 'BA', 'ME', 'MK', 'RS', 'XK', 'MD', 'UA',
};
const _gulfCountries = {'SA', 'AE', 'QA', 'KW', 'BH', 'OM'};

const _letterCountries = {'US', 'CA', 'MX', 'CO', 'VE', 'CL', 'PH', 'CR', 'GT', 'PA', 'DO', 'PR', 'NI', 'HN', 'SV', 'BO'};
const _monthFirstCountries = {'US', 'PH', 'FM', 'PW', 'MH'};
const _yearFirstCountries = {'CN', 'JP', 'KR', 'TW', 'HU', 'LT', 'IR', 'MN', 'KP'};

/// The person's region settings, read from anywhere without a context. The settings screen updates it when something is chosen.
abstract final class Region {
  static PaperChoice paperChoice = PaperChoice.auto;
  static DateStyle dateChoice = DateStyle.auto;

  /// The region used for "automatic"; the phone's own when null.
  static String? countryOverride;

  static ToolRegion toolChoice = ToolRegion.auto;

  /// Show the tools of every country, not only the person's own.
  static bool showAllTools = false;

  /// Told when the tool region or the "show all" switch changes, so the Tools page can redraw.
  static final ValueNotifier<int> toolsChanged = ValueNotifier(0);

  /// The group of country tools shown first: the chosen one, or the one for the country of the phone.
  static ToolRegion get toolRegion {
    if (toolChoice != ToolRegion.auto) return toolChoice;
    final c = country?.toUpperCase();
    if (c == 'IN') return ToolRegion.india;
    if (c == 'US') return ToolRegion.usa;
    if (_europeCountries.contains(c)) return ToolRegion.europe;
    if (_gulfCountries.contains(c)) return ToolRegion.gulf;
    return ToolRegion.other;
  }

  static String? get country => countryOverride ?? PlatformDispatcher.instance.locale.countryCode;

  static void apply({required PaperChoice paper, required DateStyle date, ToolRegion tools = ToolRegion.auto, bool showAll = false}) {
    paperChoice = paper;
    dateChoice = date;
    if (tools != toolChoice || showAll != showAllTools) {
      toolChoice = tools;
      showAllTools = showAll;
      toolsChanged.value++;
    }
  }

  /// Paper is US Letter, not A4.
  static bool get letter => switch (paperChoice) {
    PaperChoice.letter => true,
    PaperChoice.a4 => false,
    PaperChoice.auto => _letterCountries.contains(country?.toUpperCase()),
  };

  static double get paperWidthMm => letter ? 215.9 : 210;
  static double get paperHeightMm => letter ? 279.4 : 297;

  /// The order dates are written in: never [DateStyle.auto].
  static DateStyle get dateStyle {
    if (dateChoice != DateStyle.auto) return dateChoice;
    final c = country?.toUpperCase();
    if (_monthFirstCountries.contains(c)) return DateStyle.monthFirst;
    if (_yearFirstCountries.contains(c)) return DateStyle.yearFirst;
    return DateStyle.dayFirst;
  }
}
