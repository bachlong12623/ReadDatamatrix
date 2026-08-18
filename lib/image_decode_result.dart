/// Kết quả quét ảnh tĩnh.
class ImageDecodeResult {
  const ImageDecodeResult({
    required this.text,
    this.variant,
    this.engine,
  });

  final String text;
  final String? variant;
  final String? engine;

  String get label {
    final parts = <String>[];
    if (engine != null && engine!.isNotEmpty) parts.add(engine!);
    if (variant != null && variant!.isNotEmpty) parts.add(variant!);
    return parts.isEmpty ? text : parts.join(' · ');
  }
}
