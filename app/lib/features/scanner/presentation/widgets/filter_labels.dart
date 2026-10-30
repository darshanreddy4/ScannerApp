import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_icons.dart';
import '../../domain/entities/filter_settings.dart';

extension ScanFilterUi on ScanFilter {
  String get label => switch (this) {
    ScanFilter.original => 'Original',
    ScanFilter.auto => 'Auto',
    ScanFilter.magicColor => 'Clean',
    ScanFilter.documentBw => 'B&W',
    ScanFilter.sharpBw => 'Sharp B&W',
    ScanFilter.grayscale => 'Grey',
    ScanFilter.whiteboard => 'Whiteboard',
    ScanFilter.vivid => 'Vivid',
    ScanFilter.warm => 'Warm',
    ScanFilter.cool => 'Cool',
    ScanFilter.noir => 'Noir',
    ScanFilter.handwriting => 'Handwriting',
    ScanFilter.pencil => 'Pencil',
    ScanFilter.notebook => 'Notebook',
  };

  /// One line on what it does and when to use it.
  String get hint => switch (this) {
    ScanFilter.original => 'The picture exactly as it was taken.',
    ScanFilter.auto => 'Balances light and colour. Good for most photos and papers.',
    ScanFilter.magicColor => 'Evens out the lighting and whitens the paper, keeping colour. For printed pages.',
    ScanFilter.documentBw => 'Black text on white paper with smooth edges. Keeps pencil and stamps.',
    ScanFilter.sharpBw => 'Pure black and white, smallest files. For clear printed text.',
    ScanFilter.grayscale => 'Neutral grey with balanced contrast.',
    ScanFilter.whiteboard => 'White board, dark ink, vivid markers.',
    ScanFilter.vivid => 'Richer colour and extra punch. For photos.',
    ScanFilter.warm => 'A warmer white balance.',
    ScanFilter.cool => 'A cooler white balance.',
    ScanFilter.noir => 'Dramatic black and white with deep blacks.',
    ScanFilter.handwriting => 'Handwritten notes: a clean white page, darker ink, and the colour of the pen kept.',
    ScanFilter.pencil => 'Faint pencil made darker and clearer, in grey.',
    ScanFilter.notebook => 'Takes the ruled lines of a notebook page away and keeps the writing.',
  };

  IconData get icon => switch (this) {
    ScanFilter.original => AppIcons.filterOriginal,
    ScanFilter.auto => AppIcons.filterAuto,
    ScanFilter.magicColor => AppIcons.filterMagic,
    ScanFilter.documentBw => AppIcons.filterDocument,
    ScanFilter.sharpBw => AppIcons.filterSharp,
    ScanFilter.grayscale => AppIcons.filterGray,
    ScanFilter.whiteboard => AppIcons.filterBoard,
    ScanFilter.vivid => AppIcons.filterVivid,
    ScanFilter.warm => AppIcons.filterWarm,
    ScanFilter.cool => AppIcons.filterCool,
    ScanFilter.noir => AppIcons.filterNoir,
    ScanFilter.handwriting => AppIcons.filterHandwriting,
    ScanFilter.pencil => AppIcons.filterPencil,
    ScanFilter.notebook => AppIcons.filterNotebook,
  };
}
