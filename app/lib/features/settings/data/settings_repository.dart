import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/i18n/app_language.dart';
import '../../../core/utils/region.dart';
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
  static const _remind = 'expiry_reminders';
  static const _names = 'reminder_show_names';
  static const _autoName = 'auto_name_scans';
  static const _folders = 'smart_folders';
  static const _paper = 'paper_choice';
  static const _dates = 'date_style';
  static const _language = 'app_language';
  static const _toolRegion = 'tool_region';
  static const _showAllTools = 'show_all_tools';
  static const _photoDefaults = 'photo_defaults_original';
  static const _wideCamera = 'camera_wide_default';

  @override
  Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    const d = AppSettings();
    // Earlier versions defaulted to a colour filter and a cropped 16:9 camera; photos now start untouched, once.
    if (!(p.getBool(_photoDefaults) ?? false)) {
      await p.setString(_filter, d.defaultFilter.name);
      await p.setString(_camera, d.cameraQuality.name);
      await p.setBool(_photoDefaults, true);
    }
    // Full sensor leaves the preview and the photo with different framing on some phones, so everyone starts on Wide 4K again, once.
    if (!(p.getBool(_wideCamera) ?? false)) {
      await p.setString(_camera, d.cameraQuality.name);
      await p.setBool(_wideCamera, true);
    }
    return AppSettings(
      showCropAfterCapture: p.getBool(_crop) ?? d.showCropAfterCapture,
      autoCapture: p.getBool(_auto) ?? d.autoCapture,
      defaultFilter: ScanFilter.values.asNameMap()[p.getString(_filter)] ?? d.defaultFilter,
      exportQuality: ExportQuality.values.asNameMap()[p.getString(_quality)] ?? d.exportQuality,
      cameraQuality: CameraQuality.values.asNameMap()[p.getString(_camera)] ?? d.cameraQuality,
      editSavedDocuments: p.getBool(_edit) ?? d.editSavedDocuments,
      ocrScript: OcrScript.values.asNameMap()[p.getString(_ocr)] ?? d.ocrScript,
      interfaceSize: InterfaceSize.values.asNameMap()[p.getString(_size)] ?? d.interfaceSize,
      expiryReminders: p.getBool(_remind) ?? d.expiryReminders,
      reminderShowNames: p.getBool(_names) ?? d.reminderShowNames,
      autoName: p.getBool(_autoName) ?? d.autoName,
      smartFolders: p.getBool(_folders) ?? d.smartFolders,
      paper: PaperChoice.values.asNameMap()[p.getString(_paper)] ?? d.paper,
      dateStyle: DateStyle.values.asNameMap()[p.getString(_dates)] ?? d.dateStyle,
      language: AppLanguage.values.asNameMap()[p.getString(_language)] ?? d.language,
      toolRegion: ToolRegion.values.asNameMap()[p.getString(_toolRegion)] ?? d.toolRegion,
      showAllTools: p.getBool(_showAllTools) ?? d.showAllTools,
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
    await p.setBool(_remind, s.expiryReminders);
    await p.setBool(_names, s.reminderShowNames);
    await p.setBool(_autoName, s.autoName);
    await p.setBool(_folders, s.smartFolders);
    await p.setString(_paper, s.paper.name);
    await p.setString(_dates, s.dateStyle.name);
    await p.setString(_language, s.language.name);
    await p.setString(_toolRegion, s.toolRegion.name);
    await p.setBool(_showAllTools, s.showAllTools);
    await p.setBool(_photoDefaults, true);
    await p.setBool(_wideCamera, true);
  }
}
