import 'package:equatable/equatable.dart';

import '../../export/domain/entities/export_options.dart';
import '../../ocr/domain/ocr_models.dart';
import '../../scanner/domain/entities/filter_settings.dart';

/// Photo resolution used by the in-app camera. Higher values keep more detail but use more memory.
enum CameraQuality {
  standard('Full HD (fastest)'),
  high('4K (recommended)'),
  maximum('Maximum (largest files)');

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
    this.defaultFilter = ScanFilter.magicColor,
    this.exportQuality = ExportQuality.high,
    this.cameraQuality = CameraQuality.high,
    this.editSavedDocuments = true,
    this.ocrScript = OcrScript.latin,
    this.interfaceSize = InterfaceSize.medium,
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

  AppSettings copyWith({
    bool? showCropAfterCapture,
    bool? autoCapture,
    ScanFilter? defaultFilter,
    ExportQuality? exportQuality,
    CameraQuality? cameraQuality,
    bool? editSavedDocuments,
    OcrScript? ocrScript,
    InterfaceSize? interfaceSize,
  }) => AppSettings(
    showCropAfterCapture: showCropAfterCapture ?? this.showCropAfterCapture,
    autoCapture: autoCapture ?? this.autoCapture,
    defaultFilter: defaultFilter ?? this.defaultFilter,
    exportQuality: exportQuality ?? this.exportQuality,
    cameraQuality: cameraQuality ?? this.cameraQuality,
    editSavedDocuments: editSavedDocuments ?? this.editSavedDocuments,
    ocrScript: ocrScript ?? this.ocrScript,
    interfaceSize: interfaceSize ?? this.interfaceSize,
  );

  @override
  List<Object?> get props => [showCropAfterCapture, autoCapture, defaultFilter, exportQuality, cameraQuality, editSavedDocuments, ocrScript, interfaceSize];
}
