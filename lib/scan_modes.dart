/// Chế độ quét — điều chỉnh tốc độ, timeout và zoom mặc định.
enum ScanMode {
  /// Cân bằng tốc độ / độ chính xác.
  balanced,

  /// Mã chấm, tương phản thấp — quét chậm hơn, zoom gần hơn.
  dotLowContrast,

  /// Thử mọi biến thể — chậm nhất, bắt được nhiều loại mã nhất.
  aggressive,
}

extension ScanModeX on ScanMode {
  String get label => switch (this) {
        ScanMode.balanced => 'Cân bằng',
        ScanMode.dotLowContrast => 'Chấm / thấp',
        ScanMode.aggressive => 'Mạnh',
      };

  String get hint => switch (this) {
        ScanMode.balanced => 'Vuông · chữ nhật · đảo màu',
        ScanMode.dotLowContrast => 'Mã chấm · tương phản thấp · zoom 2×',
        ScanMode.aggressive => 'Đa biến thể · zoom 4× · quét ảnh',
      };

  /// Timeout giữa các frame (ms). Web iOS dùng giá trị cao hơn.
  int detectionTimeoutMs({required bool iosWeb}) => switch (this) {
        ScanMode.balanced => iosWeb ? 100 : 200,
        ScanMode.dotLowContrast => iosWeb ? 140 : 280,
        ScanMode.aggressive => iosWeb ? 180 : 350,
      };

  /// Zoom mặc định gợi ý khi chọn chế độ.
  double get defaultZoom => switch (this) {
        ScanMode.balanced => 1.0,
        ScanMode.dotLowContrast => 2.0,
        ScanMode.aggressive => 2.0,
      };

  /// Bật auto-zoom trên Android khi mã xa camera.
  bool get autoZoom => this == ScanMode.aggressive;

  /// Tỷ lệ crop trung tâm khi giả lập zoom trên web (1 = full frame).
  List<double> get webCropScales => switch (this) {
        ScanMode.balanced => const [1.0, 0.72, 0.55],
        ScanMode.dotLowContrast => const [1.0, 0.65, 0.48, 0.35],
        ScanMode.aggressive => const [1.0, 0.75, 0.58, 0.42, 0.30],
      };
}

/// Mức zoom camera (1× / 2× / 4×).
enum ScanZoom {
  x1(1.0, '1×'),
  x2(2.0, '2×'),
  x4(4.0, '4×');

  const ScanZoom(this.scale, this.label);

  final double scale;
  final String label;

  static ScanZoom nearest(double scale) {
    if (scale >= 3.0) return ScanZoom.x4;
    if (scale >= 1.5) return ScanZoom.x2;
    return ScanZoom.x1;
  }
}
