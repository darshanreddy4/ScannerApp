import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Single source of truth for iconography (Phosphor, consistent stroke weight).
/// Screens must reference icons through this class, never raw glyphs or emoji.
abstract final class AppIcons {
  static const IconData home = PhosphorIconsRegular.house;
  static const IconData homeActive = PhosphorIconsFill.house;
  static const IconData settings = PhosphorIconsRegular.gearSix;
  static const IconData settingsActive = PhosphorIconsFill.gearSix;
  static const IconData library = PhosphorIconsRegular.files;
  static const IconData ai = PhosphorIconsRegular.sparkle;

  static const IconData scan = PhosphorIconsRegular.scan;
  static const IconData camera = PhosphorIconsRegular.camera;
  static const IconData gallery = PhosphorIconsRegular.image;
  static const IconData importFile = PhosphorIconsRegular.fileArrowUp;
  static const IconData flash = PhosphorIconsRegular.lightning;
  static const IconData flashOff = PhosphorIconsRegular.lightningSlash;
  static const IconData autoCapture = PhosphorIconsRegular.crosshairSimple;

  static const IconData close = PhosphorIconsRegular.x;
  static const IconData back = PhosphorIconsRegular.caretLeft;
  static const IconData next = PhosphorIconsRegular.caretRight;
  static const IconData check = PhosphorIconsBold.check;
  static const IconData add = PhosphorIconsRegular.plus;
  static const IconData more = PhosphorIconsRegular.dotsThreeVertical;
  static const IconData search = PhosphorIconsRegular.magnifyingGlass;

  static const IconData crop = PhosphorIconsRegular.crop;
  static const IconData autoDetect = PhosphorIconsRegular.selectionPlus;
  static const IconData fullFrame = PhosphorIconsRegular.frameCorners;
  static const IconData rotate = PhosphorIconsRegular.arrowClockwise;
  static const IconData reset = PhosphorIconsRegular.arrowCounterClockwise;

  static const IconData filterOriginal = PhosphorIconsRegular.imageSquare;
  static const IconData filterDocument = PhosphorIconsRegular.fileText;
  static const IconData filterMagic = PhosphorIconsRegular.magicWand;
  static const IconData filterGray = PhosphorIconsRegular.circleHalf;
  static const IconData brightness = PhosphorIconsRegular.sun;
  static const IconData contrast = PhosphorIconsRegular.circleHalfTilt;

  static const IconData pdf = PhosphorIconsRegular.filePdf;
  static const IconData docx = PhosphorIconsRegular.fileDoc;
  static const IconData share = PhosphorIconsRegular.shareNetwork;
  static const IconData export = PhosphorIconsRegular.export;
  static const IconData delete = PhosphorIconsRegular.trash;
  static const IconData edit = PhosphorIconsRegular.pencilSimple;
  static const IconData retake = PhosphorIconsRegular.cameraRotate;
  static const IconData dragHandle = PhosphorIconsRegular.dotsSixVertical;
  static const IconData document = PhosphorIconsRegular.fileImage;
  static const IconData emptyDocs = PhosphorIconsLight.folderOpen;

  static const IconData lock = PhosphorIconsRegular.lockKey;
  static const IconData shield = PhosphorIconsRegular.shieldCheck;
  static const IconData premium = PhosphorIconsRegular.crown;
  static const IconData warning = PhosphorIconsRegular.warningCircle;
  static const IconData storage = PhosphorIconsRegular.hardDrives;
  static const IconData quality = PhosphorIconsRegular.slidersHorizontal;
  static const IconData info = PhosphorIconsRegular.info;
}
