enum ExportFormat {
  pdf('pdf', 'application/pdf'),
  docx('docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');

  const ExportFormat(this.extension, this.mimeType);
  final String extension;
  final String mimeType;
}

enum ExportQuality {
  /// Embeds stored images untouched.
  high(null, 0),
  medium(1800, 82),
  low(1200, 70);

  const ExportQuality(this.maxSide, this.jpegQuality);
  final int? maxSide;
  final int jpegQuality;

  String get label => switch (this) {
        ExportQuality.high => 'High',
        ExportQuality.medium => 'Medium',
        ExportQuality.low => 'Low (smallest file)',
      };
}
