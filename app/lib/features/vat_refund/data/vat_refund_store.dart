import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/vat_refund.dart';

const _maxSide = 1600;

/// A receipt photo with its orientation fixed and its longest side at most 1600 px; null when the bytes are not a picture.
Uint8List? shrinkReceiptPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  final longest = math.max(image.width, image.height);
  if (longest > _maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: _maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: _maxSide, interpolation: img.Interpolation.average);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

/// Keeps the receipts and their pictures in the app's private storage.
class VatRefundStore {
  VatRefundStore({Future<Directory> Function()? appDir}) : _appDir = appDir ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _appDir;
  static const _key = 'vat_refund_receipts';
  int _counter = 0;

  Future<List<VatReceipt>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return const [];
    try {
      return [for (final o in jsonDecode(raw) as List<dynamic>) ?VatReceipt.fromJson(o)];
    } on Object {
      return const [];
    }
  }

  Future<void> save(List<VatReceipt> receipts) async {
    final prefs = await SharedPreferences.getInstance();
    if (receipts.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode([for (final r in receipts) r.toJson()]));
    }
  }

  String newId() => '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  /// Stores a smaller copy of the picture and returns where it is; null when the file is not a picture.
  Future<String?> addPhoto(String sourcePath) async {
    final small = await compute(shrinkReceiptPhoto, await File(sourcePath).readAsBytes());
    if (small == null) return null;
    final dir = await Directory(p.join((await _appDir()).path, 'vat_refund')).create(recursive: true);
    final file = File(p.join(dir.path, '${newId()}.jpg'));
    await file.writeAsBytes(small, flush: true);
    return file.path;
  }

  Future<void> deletePhoto(String? path) async {
    if (path == null) return;
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  /// Removes every receipt and picture.
  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(_key);
    final dir = Directory(p.join((await _appDir()).path, 'vat_refund'));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
