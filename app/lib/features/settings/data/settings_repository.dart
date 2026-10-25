import 'package:shared_preferences/shared_preferences.dart';

import '../../export/domain/entities/export_options.dart';
import '../../ocr/domain/ocr_models.dart';
import '../../scanner/domain/entities/filter_settings.dart';
import '../domain/app_settings.dart';

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class SettingsRepositoryImpl implements SettingsRepository {
  static const _crop = 'show_crop_after_capture';
  static const _auto = 'auto_capture';
  static const _filter = 'default_filter';
  static const _quality = 'export_quality';
  static const _camera = 'camera_quality';
  static const _edit = 'feature_edit_saved_documents';
  static const _ocr = 'ocr_script';
  static const _size = 'interface_size';

  @override
  Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    const d = AppSettings();
    return AppSettings(
      showCropAfterCapture: p.getBool(_crop) ?? d.showCropAfterCapture,
      autoCapture: p.getBool(_auto) ?? d.autoCapture,
      defaultFilter: ScanFilter.values.asNameMap()[p.getString(_filter)] ?? d.defaultFilter,
      exportQuality: ExportQuality.values.asNameMap()[p.getString(_quality)] ?? d.exportQuality,
      cameraQuality: CameraQuality.values.asNameMap()[p.getString(_camera)] ?? d.cameraQuality,
      editSavedDocuments: p.getBool(_edit) ?? d.editSavedDocuments,
      ocrScript: OcrScript.values.asNameMap()[p.getString(_ocr)] ?? d.ocrScript,
      interfaceSize: InterfaceSize.values.asNameMap()[p.getString(_size)] ?? d.interfaceSize,
    );
  }

  @override
  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_crop, s.showCropAfterCapture);
    await p.setBool(_auto, s.autoCapture);
    await p.setString(_filter, s.defaultFilter.name);
    await p.setString(_quality, s.exportQuality.name);
    await p.setString(_camera, s.cameraQuality.name);
    await p.setBool(_edit, s.editSavedDocuments);
    await p.setString(_ocr, s.ocrScript.name);
    await p.setString(_size, s.interfaceSize.name);
  }
}
