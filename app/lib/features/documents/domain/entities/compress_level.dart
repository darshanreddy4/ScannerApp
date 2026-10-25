enum CompressLevel {
  medium('Medium', 'Sharp text, about half the size', 2000, 75),
  small('Small', 'Smallest file, slightly softer', 1400, 60);

  const CompressLevel(this.label, this.description, this.maxSide, this.quality);
  final String label;
  final String description;
  final int maxSide;
  final int quality;
}
