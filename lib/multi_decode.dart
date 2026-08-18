/// Kết quả decode từ một engine.
class MultiDecodeHit {
  const MultiDecodeHit({
    required this.text,
    required this.engine,
    this.variant,
  });

  final String text;
  final String engine;
  final String? variant;

  String get label {
    final parts = <String>[engine];
    if (variant != null && variant!.isNotEmpty) parts.add(variant!);
    return parts.join(' · ');
  }
}
