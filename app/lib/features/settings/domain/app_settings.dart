import 'package:equatable/equatable.dart';

import '../../../core/i18n/app_language.dart';
import '../../../core/utils/region.dart';
import '../../export/domain/entities/export_options.dart';
import '../../ocr/domain/ocr_models.dart';
import '../../scanner/domain/entities/filter_settings.dart';

/// Photo resolution used by the in-app camera. Higher values keep more detail but use more memory.
enum CameraQuality {
  standard('Wide Full HD (fastest)'),
  high('Wide 4K (recommended)'),
  maximum('Full sensor (the preview may frame differently)');

  const CameraQuality(this.label);
  final String label;
}

/// Overall size of text, icons and buttons.
enum InterfaceSize {
  small('Small', 0.9),
  medium('Medium', 1.0),
  large('Large', 1.15);

  const InterfaceSize(this.label, this.scale);
  final String label;
  final double scale;
}

class AppSettings extends Equatable {
  const AppSettings({
    this.showCropAfterCapture = true,
    this.autoCapture = true,
    this.defaultFilter = ScanFilter.original,
    this.exportQuality = ExportQuality.high,
    this.cameraQuality = CameraQuality.high,
    this.editSavedDocuments = true,
    this.ocrScript = OcrScript.latin,
    this.interfaceSize = InterfaceSize.medium,
    this.expiryReminders = true,
    this.reminderShowNames = false,
    this.autoName = true,
    this.smartFolders = true,
    this.paper = PaperChoice.auto,
    this.dateStyle = DateStyle.auto,
    this.language = AppLanguage.system,
    this.toolRegion = ToolRegion.auto,
    this.showAllTools = false,
  });

  final bool showCropAfterCapture;
  final bool autoCapture;
  final ScanFilter defaultFilter;
  final ExportQuality exportQuality;
  final CameraQuality cameraQuality;

  /// Owner switch for the premium feature "edit saved documents".
  final bool editSavedDocuments;

  /// Writing system used when reading text from pages.
  final OcrScript ocrScript;
  final InterfaceSize interfaceSize;

  /// Notify before a document's expiry date.
  final bool expiryReminders;

  /// Put the document's name in the reminder; off keeps names off the lock screen.
  final bool reminderShowNames;

  /// Name new scans from the heading or date on the first page, when the name was not chosen.
  final bool autoName;

  /// File receipts, IDs, cards, books and whiteboards into folders of their own kind.
  final bool smartFolders;

  /// Paper for pages the app lays out and prints, and the way dates are written; automatic follows the region of the phone.
  final PaperChoice paper;
  final DateStyle dateStyle;

  /// The language of menus and messages.
  final AppLanguage language;

  /// Which country's tools come first on the Tools page, and whether every country's tools are shown.
  final ToolRegion toolRegion;
  final bool showAllTools;

  AppSettings copyWith({
    bool? showCropAfterCapture,
    bool? autoCapture,
    ScanFilter? defaultFilter,
    ExportQuality? exportQuality,
    CameraQuality? cameraQuality,
    bool? editSavedDocuments,
    OcrScript? ocrScript,
    InterfaceSize? interfaceSize,
    bool? expiryReminders,
    bool? reminderShowNames,
    bool? autoName,
    bool? smartFolders,
    PaperChoice? paper,
    DateStyle? dateStyle,
    AppLanguage? language,
    ToolRegion? toolRegion,
    bool? showAllTools,
  }) => AppSettings(
    showCropAfterCapture: showCropAfterCapture ?? this.showCropAfterCapture,
    autoCapture: autoCapture ?? this.autoCapture,
    defaultFilter: defaultFilter ?? this.defaultFilter,
    exportQuality: exportQuality ?? this.exportQuality,
    cameraQuality: cameraQuality ?? this.cameraQuality,
    editSavedDocuments: editSavedDocuments ?? this.editSavedDocuments,
    ocrScript: ocrScript ?? this.ocrScript,
    interfaceSize: interfaceSize ?? this.interfaceSize,
    expiryReminders: expiryReminders ?? this.expiryReminders,
    reminderShowNames: reminderShowNames ?? this.reminderShowNames,
    autoName: autoName ?? this.autoName,
    smartFolders: smartFolders ?? this.smartFolders,
    paper: paper ?? this.paper,
    dateStyle: dateStyle ?? this.dateStyle,
    language: language ?? this.language,
    toolRegion: toolRegion ?? this.toolRegion,
    showAllTools: showAllTools ?? this.showAllTools,
  );

  @override
  List<Object?> get props => [
    showCropAfterCapture,
    autoCapture,
    defaultFilter,
    exportQuality,
    cameraQuality,
    editSavedDocuments,
    ocrScript,
    interfaceSize,
    expiryReminders,
    reminderShowNames,
    autoName,
    smartFolders,
    paper,
    dateStyle,
    language,
    toolRegion,
    showAllTools,
  ];
}
