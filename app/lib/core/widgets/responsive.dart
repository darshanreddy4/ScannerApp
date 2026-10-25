import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Material window-size breakpoints, in logical pixels of width.
abstract final class Breakpoints {
  /// From here a navigation rail replaces the bottom bar and content is capped in width.
  static const double medium = 600;

  /// From here screens can show two panes side by side.
  static const double expanded = 840;
}

/// List padding that keeps readable content in a centred column on tablets and leaves phones unchanged.
EdgeInsets contentPadding(BuildContext context, {double base = AppSpacing.md, double maxWidth = 720, double? vertical}) {
  final width = MediaQuery.sizeOf(context).width;
  final side = ((width - maxWidth) / 2).clamp(base, double.infinity);
  return EdgeInsets.symmetric(horizontal: side, vertical: vertical ?? base);
}

/// Centres [child] and caps its width; use for screens that are not lists.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 720});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Locks phones to portrait; tablets and foldables rotate freely (Android ignores portrait locks on large screens anyway).
class OrientationPolicy extends StatefulWidget {
  const OrientationPolicy({super.key, required this.child, this.apply = _apply});
  final Widget child;
  final Future<void> Function(List<DeviceOrientation> orientations) apply;

  static Future<void> _apply(List<DeviceOrientation> orientations) => SystemChrome.setPreferredOrientations(orientations);

  @override
  State<OrientationPolicy> createState() => _OrientationPolicyState();
}

class _OrientationPolicyState extends State<OrientationPolicy> {
  bool? _large;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final large = MediaQuery.sizeOf(context).shortestSide >= Breakpoints.medium;
    if (large == _large) return;
    _large = large;
    widget.apply(large ? DeviceOrientation.values : const [DeviceOrientation.portraitUp]);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
