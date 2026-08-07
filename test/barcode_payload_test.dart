import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:read_datamatrix/barcode_payload.dart';

void main() {
  test('extracts rawValue for GS1-like payload with GS separators', () {
    const payload = '0109501101020917\u001d21ABC123';
    final barcode = Barcode(
      format: BarcodeFormat.dataMatrix,
      rawValue: '  $payload  ',
    );

    expect(extractBarcodePayload(barcode), payload);
  });

  test('falls back to latin-1 bytes when rawValue missing', () {
    final bytes = Uint8List.fromList('Café'.codeUnits);
    final barcode = Barcode(
      format: BarcodeFormat.dataMatrix,
      rawDecodedBytes: DecodedBarcodeBytes(bytes: bytes),
    );

    expect(extractBarcodePayload(barcode), 'Café');
  });

  test('hex-encodes opaque binary payloads', () {
    final bytes = Uint8List.fromList([0x00, 0x01, 0x02, 0xFF]);
    final barcode = Barcode(
      format: BarcodeFormat.dataMatrix,
      rawDecodedBytes: DecodedBarcodeBytes(bytes: bytes),
    );

    expect(extractBarcodePayload(barcode), '00 01 02 ff');
  });
}
