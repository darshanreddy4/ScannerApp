import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_icons.dart';
import '../../domain/entities/filter_settings.dart';

extension ScanFilterUi on ScanFilter {
  String get label => switch (this) {
    ScanFilter.original => 'Original',
    ScanFilter.documentBw => 'Document B&W',
    ScanFilter.magicColor => 'Magic color',
    ScanFilter.grayscale => 'Grayscale',
  };

  IconData get icon => switch (this) {
    ScanFilter.original => AppIcons.filterOriginal,
    ScanFilter.documentBw => AppIcons.filterDocument,
    ScanFilter.magicColor => AppIcons.filterMagic,
    ScanFilter.grayscale => AppIcons.filterGray,
  };
}
