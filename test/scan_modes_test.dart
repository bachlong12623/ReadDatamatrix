import 'package:read_datamatrix/scan_modes.dart';
import 'package:test/test.dart';

void main() {
  group('ScanMode', () {
    test('timeout tăng theo độ mạnh', () {
      expect(
        ScanMode.balanced.detectionTimeoutMs(iosWeb: false),
        lessThan(ScanMode.aggressive.detectionTimeoutMs(iosWeb: false)),
      );
    });

    test('defaultZoom', () {
      expect(ScanMode.balanced.defaultZoom, 1.0);
      expect(ScanMode.dotLowContrast.defaultZoom, 2.0);
    });

    test('webCropScales có full frame', () {
      for (final mode in ScanMode.values) {
        expect(mode.webCropScales.first, 1.0);
      }
    });
  });

  group('ScanZoom', () {
    test('nearest', () {
      expect(ScanZoom.nearest(1.0), ScanZoom.x1);
      expect(ScanZoom.nearest(2.0), ScanZoom.x2);
      expect(ScanZoom.nearest(4.0), ScanZoom.x4);
    });
  });
}
