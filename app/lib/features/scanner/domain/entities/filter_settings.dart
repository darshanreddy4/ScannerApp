import 'package:equatable/equatable.dart';

/// Saved by name, so new filters are only ever added at the end and existing names keep their meaning.
enum ScanFilter { original, documentBw, magicColor, grayscale, auto, sharpBw, whiteboard, vivid, warm, cool, noir, handwriting, pencil, notebook }

/// The order the filters are offered in: the everyday ones first, then documents, then colour looks.
const filterOrder = [
  ScanFilter.original,
  ScanFilter.auto,
  ScanFilter.magicColor,
  ScanFilter.documentBw,
  ScanFilter.sharpBw,
  ScanFilter.grayscale,
  ScanFilter.whiteboard,
  ScanFilter.handwriting,
  ScanFilter.pencil,
  ScanFilter.notebook,
  ScanFilter.vivid,
  ScanFilter.warm,
  ScanFilter.cool,
  ScanFilter.noir,
];

class FilterSettings extends Equatable {
  const FilterSettings({this.filter = ScanFilter.original, this.brightness = 0, this.contrast = 0});

  final ScanFilter filter;

  /// -100..100
  final double brightness;

  /// -100..100
  final double contrast;

  FilterSettings copyWith({ScanFilter? filter, double? brightness, double? contrast}) =>
      FilterSettings(filter: filter ?? this.filter, brightness: brightness ?? this.brightness, contrast: contrast ?? this.contrast);

  @override
  List<Object?> get props => [filter, brightness, contrast];
}
