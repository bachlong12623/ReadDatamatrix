import 'dart:convert';
import 'dart:typed_data';

import 'package:mobile_scanner/mobile_scanner.dart';

/// Trích payload Data Matrix đa dạng: text, GS1 (FNC1/GS), binary, Latin-1.
String? extractBarcodePayload(Barcode barcode) {
  final fromRaw = _normalizeText(barcode.rawValue);
  if (fromRaw != null) return fromRaw;

  final fromDisplay = _normalizeText(barcode.displayValue);
  if (fromDisplay != null) return fromDisplay;

  final bytes = _bytesOf(barcode);
  if (bytes == null || bytes.isEmpty) return null;

  return _decodeBytes(bytes);
}

Uint8List? _bytesOf(Barcode barcode) {
  final decoded = barcode.rawDecodedBytes;
  switch (decoded) {
    case DecodedBarcodeBytes(:final bytes):
      return bytes;
    case DecodedVisionBarcodeBytes(:final bytes, :final rawBytes):
      return bytes ?? rawBytes;
    case null:
      // ignore: deprecated_member_use
      return barcode.rawBytes;
  }
}

String? _normalizeText(String? value) {
  if (value == null) return null;
  // Giữ GS (0x1D), RS (0x1E), EOT (0x04) của GS1 — chỉ trim khoảng trắng thường.
  final trimmed = value.replaceAll(RegExp(r'^[\s\uFEFF]+|[\s\uFEFF]+$'), '');
  return trimmed.isEmpty ? null : trimmed;
}

String _decodeBytes(Uint8List bytes) {
  // Ưu tiên UTF-8 (nhiều Data Matrix công nghiệp / Unicode).
  try {
    final utf8Text = utf8.decode(bytes);
    final normalized = _normalizeText(utf8Text);
    if (normalized != null && !_looksMostlyBinary(normalized)) {
      return normalized;
    }
  } on FormatException {
    // Fall through.
  }

  // Latin-1 / ISO-8859-1 — phổ biến với Vision/iOS và payload 8-bit.
  final latin = _normalizeText(latin1.decode(bytes));
  if (latin != null && !_looksMostlyBinary(latin)) {
    return latin;
  }

  // Binary thuần: hex để copy/ghi nhận được.
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}

bool _looksMostlyBinary(String text) {
  if (text.isEmpty) return true;
  var nonPrintable = 0;
  for (final unit in text.codeUnits) {
    final ok =
        unit == 0x09 ||
        unit == 0x0A ||
        unit == 0x0D ||
        unit == 0x04 || // EOT (GS1)
        unit == 0x1D || // GS
        unit == 0x1E || // RS
        (unit >= 0x20 && unit <= 0x7E) ||
        unit >= 0xA0;
    if (!ok) nonPrintable++;
  }
  return nonPrintable / text.length > 0.25;
}
