import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/cv.dart';

/// Scales a photo down to at most 600 pixels on a side and saves it as a JPEG, so the CV stays small. Runs in a background isolate.
Uint8List shrinkPhoto(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) throw const FormatException('Not a picture');
  image = img.bakeOrientation(image);
  const maxSide = 600;
  if (image.width > maxSide || image.height > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 86));
}

/// Keeps the CV being written, and its photo, on the phone only.
class CvStore {
  CvStore({required Future<Directory> Function() appDir}) : _appDir = appDir;
  final Future<Directory> Function() _appDir;
  static const _key = 'cv_draft';

  Future<File> _photoFile() async => File(p.join((await _appDir()).path, 'cv', 'photo.jpg'));

  Future<CvData> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return const CvData();
    try {
      return CvData.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } on Object {
      return const CvData();
    }
  }

  Future<void> save(CvData data) async => (await SharedPreferences.getInstance()).setString(_key, jsonEncode(data.toJson()));

  Future<Uint8List?> loadPhoto() async {
    final f = await _photoFile();
    return await f.exists() ? f.readAsBytes() : null;
  }

  Future<void> savePhoto(Uint8List jpeg) async {
    final f = await _photoFile();
    await f.parent.create(recursive: true);
    await f.writeAsBytes(jpeg, flush: true);
  }

  Future<void> deletePhoto() async {
    final f = await _photoFile();
    if (await f.exists()) await f.delete();
  }

  /// Removes the CV and the photo.
  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(_key);
    final dir = Directory(p.join((await _appDir()).path, 'cv'));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
