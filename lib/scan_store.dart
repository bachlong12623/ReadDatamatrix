import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ScanRecord {
  const ScanRecord({required this.text, required this.at});

  final String text;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'text': text,
        'at': at.toIso8601String(),
      };

  factory ScanRecord.fromJson(Map<String, dynamic> json) {
    return ScanRecord(
      text: json['text'] as String? ?? '',
      at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Lưu tạm trên thiết bị (localStorage trên web, prefs trên native).
class ScanStore {
  ScanStore._(this._prefs);

  static const _key = 'datamatrix_scan_history_v1';
  static const maxRecords = 300;

  final SharedPreferences _prefs;

  static Future<ScanStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return ScanStore._(prefs);
  }

  List<ScanRecord> load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => ScanRecord.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.text.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<ScanRecord> records) async {
    final trimmed = records.take(maxRecords).toList();
    await _prefs.setString(
      _key,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clear() => _prefs.remove(_key);
}
