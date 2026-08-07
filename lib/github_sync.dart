import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'scan_store.dart';

class GithubSyncConfig {
  const GithubSyncConfig({
    required this.owner,
    required this.repo,
    required this.path,
    required this.token,
  });

  final String owner;
  final String repo;
  final String path;
  final String token;

  bool get isReady => token.trim().isNotEmpty;

  Map<String, String> get headers => {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer ${token.trim()}',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json',
      };

  Uri get contentsUri => Uri.https(
        'api.github.com',
        '/repos/$owner/$repo/contents/$path',
      );
}

/// Đồng bộ JSON lên GitHub (Contents API) — phù hợp dự án cá nhân 1 người.
class GithubScanSync {
  GithubScanSync(this._prefs);

  static const _tokenKey = 'github_pat_v1';
  static const _ownerKey = 'github_owner_v1';
  static const _repoKey = 'github_repo_v1';
  static const _pathKey = 'github_path_v1';

  static const defaultOwner = 'bachlong12623';
  static const defaultRepo = 'ReadDatamatrix';
  static const defaultPath = 'data/scans.json';

  final SharedPreferences _prefs;

  static Future<GithubScanSync> open() async {
    final prefs = await SharedPreferences.getInstance();
    return GithubScanSync(prefs);
  }

  GithubSyncConfig loadConfig() {
    return GithubSyncConfig(
      owner: _prefs.getString(_ownerKey) ?? defaultOwner,
      repo: _prefs.getString(_repoKey) ?? defaultRepo,
      path: _prefs.getString(_pathKey) ?? defaultPath,
      token: _prefs.getString(_tokenKey) ?? '',
    );
  }

  Future<void> saveConfig(GithubSyncConfig config) async {
    await _prefs.setString(_tokenKey, config.token.trim());
    await _prefs.setString(_ownerKey, config.owner.trim());
    await _prefs.setString(_repoKey, config.repo.trim());
    await _prefs.setString(_pathKey, config.path.trim());
  }

  Future<void> clearToken() => _prefs.remove(_tokenKey);

  /// Gộp local + remote theo `text`, giữ lần quét mới nhất.
  static List<ScanRecord> merge(
    List<ScanRecord> local,
    List<ScanRecord> remote,
  ) {
    final map = <String, ScanRecord>{};
    for (final r in [...remote, ...local]) {
      if (r.text.isEmpty) continue;
      final prev = map[r.text];
      if (prev == null || r.at.isAfter(prev.at)) {
        map[r.text] = r;
      }
    }
    final merged = map.values.toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    if (merged.length > ScanStore.maxRecords) {
      return merged.sublist(0, ScanStore.maxRecords);
    }
    return merged;
  }

  Future<({List<ScanRecord> scans, String? sha})> pull(
    GithubSyncConfig config,
  ) async {
    final res = await http.get(config.contentsUri, headers: config.headers);
    if (res.statusCode == 404) {
      return (scans: <ScanRecord>[], sha: null);
    }
    if (res.statusCode != 200) {
      throw GithubSyncException(
        'Pull thất bại (${res.statusCode}): ${_shortBody(res.body)}',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final sha = body['sha'] as String?;
    final encoded = body['content'] as String? ?? '';
    final cleaned = encoded.replaceAll('\n', '');
    final decoded = utf8.decode(base64.decode(cleaned));
    final scans = _parseDocument(decoded);
    return (scans: scans, sha: sha);
  }

  Future<List<ScanRecord>> push(
    GithubSyncConfig config,
    List<ScanRecord> local, {
    String? sha,
  }) async {
    // Re-pull để tránh ghi đè nếu có thay đổi từ máy khác.
    String? currentSha = sha;
    List<ScanRecord> remote = const [];
    try {
      final pulled = await pull(config);
      remote = pulled.scans;
      currentSha = pulled.sha;
    } catch (_) {
      // File chưa có / lỗi mạng — vẫn thử tạo mới.
    }

    final merged = merge(local, remote);
    final doc = jsonEncode({
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'scans': merged.map((e) => e.toJson()).toList(),
    });
    final payload = <String, dynamic>{
      'message': 'chore: sync DataMatrix scans (${merged.length})',
      'content': base64.encode(utf8.encode(doc)),
      'branch': 'main',
    };
    if (currentSha != null) {
      payload['sha'] = currentSha;
    }

    final res = await http.put(
      config.contentsUri,
      headers: config.headers,
      body: jsonEncode(payload),
    );

    if (res.statusCode == 409) {
      // Conflict — pull lại và đẩy lần nữa.
      final again = await pull(config);
      final retried = merge(local, again.scans);
      final doc2 = jsonEncode({
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'scans': retried.map((e) => e.toJson()).toList(),
      });
      final res2 = await http.put(
        config.contentsUri,
        headers: config.headers,
        body: jsonEncode({
          'message': 'chore: sync DataMatrix scans (${retried.length})',
          'content': base64.encode(utf8.encode(doc2)),
          'branch': 'main',
          'sha': again.sha,
        }),
      );
      if (res2.statusCode != 200 && res2.statusCode != 201) {
        throw GithubSyncException(
          'Push thất bại (${res2.statusCode}): ${_shortBody(res2.body)}',
        );
      }
      return retried;
    }

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw GithubSyncException(
        'Push thất bại (${res.statusCode}): ${_shortBody(res.body)}',
      );
    }
    return merged;
  }

  /// Pull + merge + push một vòng.
  Future<List<ScanRecord>> sync(
    GithubSyncConfig config,
    List<ScanRecord> local,
  ) async {
    if (!config.isReady) {
      throw const GithubSyncException('Chưa có GitHub token.');
    }
    final pulled = await pull(config);
    final merged = merge(local, pulled.scans);
    return push(config, merged, sha: pulled.sha);
  }

  List<ScanRecord> _parseDocument(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => ScanRecord.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.text.isNotEmpty)
          .toList();
    }
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final scans = map['scans'];
      if (scans is List) {
        return scans
            .whereType<Map>()
            .map((e) => ScanRecord.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.text.isNotEmpty)
            .toList();
      }
    }
    return [];
  }

  String _shortBody(String body) {
    if (body.length <= 180) return body;
    return '${body.substring(0, 180)}…';
  }
}

class GithubSyncException implements Exception {
  const GithubSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}
