import 'entities/scan_mode.dart';

/// The folder a kind of scan is filed into: its name and how it looks.
class SmartFolder {
  const SmartFolder(this.name, this.icon, this.color);
  final String name;
  final String icon;
  final int color;
}

/// Plain documents stay where they are made; the other kinds have a folder of their own.
SmartFolder? smartFolderFor(ScanMode mode) => switch (mode) {
  ScanMode.receipt => const SmartFolder('Receipts', 'invoice', 0xFFD97706),
  ScanMode.id => const SmartFolder('IDs', 'id', 0xFF1D4ED8),
  ScanMode.card => const SmartFolder('Business cards', 'card', 0xFF0D9488),
  ScanMode.book => const SmartFolder('Books', 'book', 0xFF9333EA),
  ScanMode.whiteboard => const SmartFolder('Whiteboards', 'office', 0xFF475569),
  ScanMode.table => const SmartFolder('Tables', 'file', 0xFF16A34A),
  ScanMode.document => null,
};
