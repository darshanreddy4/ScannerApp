import 'package:flutter/material.dart';

/// Design tokens. Neutral enterprise palette with a single blue accent.
abstract final class AppColors {
  static const primary = Color(0xFF1D4ED8);
  static const primaryDark = Color(0xFF1E3A8A);
  static const primarySoft = Color(0xFFE8EEFC);

  static const ink = Color(0xFF0F172A);
  static const inkMuted = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFF6F8FB);

  static const success = Color(0xFF15803D);
  static const warning = Color(0xFFB45309);
  static const danger = Color(0xFFB91C1C);

  static const scannerBackdrop = Color(0xFF0B1220);
  static const scannerOverlay = Color(0xFF60A5FA);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const radius = 12.0;
}
