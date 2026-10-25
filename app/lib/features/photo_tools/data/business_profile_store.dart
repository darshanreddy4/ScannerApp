import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/watermark.dart';
import '../domain/watermark_service.dart';

/// Keeps the business name, details and logo on the phone for reuse in watermarks.
class BusinessProfileStoreImpl implements BusinessProfileStore {
  BusinessProfileStoreImpl({required Future<Directory> Function() appDir}) : _appDir = appDir;

  final Future<Directory> Function() _appDir;
  static const _key = 'business_profile';
  static const logoMaxSide = 600;

  @override
  Future<BusinessProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const BusinessProfile();
    try {
      final profile = BusinessProfile.fromJson((jsonDecode(raw) as Map<String, dynamic>).cast<String, Object?>());
      final logo = profile.logoPath;
      return logo != null && !File(logo).existsSync() ? BusinessProfile(name: profile.name, details: profile.details) : profile;
    } on Object {
      return const BusinessProfile();
    }
  }

  @override
  Future<BusinessProfile> save(BusinessProfile profile, {String? newLogoSource}) async {
    final dir = Directory(p.join((await _appDir()).path, 'branding'));
    String? logoPath = profile.logoPath;

    if (newLogoSource != null) {
      final bytes = await File(newLogoSource).readAsBytes();
      final png = _logoPng(bytes);
      await dir.create(recursive: true);
      final target = File(p.join(dir.path, 'logo_${DateTime.now().microsecondsSinceEpoch}.png'));
      await target.writeAsBytes(png, flush: true);
      logoPath = target.path;
    }

    // Only the current logo is kept.
    if (await dir.exists()) {
      for (final entity in dir.listSync().whereType<File>()) {
        if (entity.path != logoPath) await entity.delete();
      }
    }

    final saved = BusinessProfile(name: profile.name.trim(), details: profile.details.trim(), logoPath: logoPath);
    final prefs = await SharedPreferences.getInstance();
    if (saved.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(saved.toJson()));
    }
    return saved;
  }

  /// A logo is kept small so every watermark stays quick, and as PNG so its transparency survives.
  static List<int> _logoPng(List<int> bytes) {
    var image = img.decodeImage(bytes as dynamic);
    if (image == null) throw const FormatException('Unsupported or damaged image');
    image = img.bakeOrientation(image);
    if (image.width > logoMaxSide || image.height > logoMaxSide) {
      image = image.width >= image.height ? img.copyResize(image, width: logoMaxSide) : img.copyResize(image, height: logoMaxSide);
    }
    return img.encodePng(image);
  }
}
