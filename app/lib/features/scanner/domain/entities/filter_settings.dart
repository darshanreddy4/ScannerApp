import 'package:equatable/equatable.dart';

enum ScanFilter { original, documentBw, magicColor, grayscale }

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
