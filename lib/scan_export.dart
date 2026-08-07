import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'scan_export_stub.dart'
    if (dart.library.js_interop) 'scan_export_web.dart' as web_export;
import 'scan_store.dart';

enum ExportFormat { csv, txt, json }

class ScanExporter {
  const ScanExporter();

  String buildContent(List<ScanRecord> records, ExportFormat format) {
    switch (format) {
      case ExportFormat.csv:
        final buf = StringBuffer('stt,thoi_gian,noi_dung\n');
        for (var i = 0; i < records.length; i++) {
          final r = records[i];
          buf.writeln(
            '${i + 1},${_csv(_formatTime(r.at))},${_csv(r.text)}',
          );
        }
        return buf.toString();
      case ExportFormat.txt:
        final buf = StringBuffer();
        for (final r in records) {
          buf.writeln('${_formatTime(r.at)}\t${r.text}');
        }
        return buf.toString();
      case ExportFormat.json:
        return const JsonEncoder.withIndent('  ').convert(
          records.map((e) => e.toJson()).toList(),
        );
    }
  }

  String fileName(ExportFormat format) {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '')
        .substring(0, 15);
    return switch (format) {
      ExportFormat.csv => 'datamatrix_$stamp.csv',
      ExportFormat.txt => 'datamatrix_$stamp.txt',
      ExportFormat.json => 'datamatrix_$stamp.json',
    };
  }

  String mimeType(ExportFormat format) => switch (format) {
        ExportFormat.csv => 'text/csv',
        ExportFormat.txt => 'text/plain',
        ExportFormat.json => 'application/json',
      };

  /// Web: tải file (Safari iPhone → Save to Files / iCloud).
  /// Native: share sheet (AirDrop, Files, Mail…).
  Future<void> exportAndShare(
    List<ScanRecord> records, {
    ExportFormat format = ExportFormat.csv,
  }) async {
    if (records.isEmpty) return;
    final content = buildContent(records, format);
    final name = fileName(format);
    final mime = mimeType(format);
    final bytes = utf8.encode(content);

    if (kIsWeb) {
      web_export.downloadTextFile(name, content, mime);
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, mimeType: mime, name: name),
        ],
        fileNameOverrides: [name],
        text: 'DataMatrix scans (${records.length})',
      ),
    );
  }

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  String _csv(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
