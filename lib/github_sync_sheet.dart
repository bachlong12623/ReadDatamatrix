import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'github_sync.dart';

Future<GithubSyncConfig?> showGithubSyncSheet({
  required BuildContext context,
  required GithubSyncConfig initial,
}) {
  return showModalBottomSheet<GithubSyncConfig>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF142028),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _GithubSyncSheet(initial: initial),
  );
}

class _GithubSyncSheet extends StatefulWidget {
  const _GithubSyncSheet({required this.initial});

  final GithubSyncConfig initial;

  @override
  State<_GithubSyncSheet> createState() => _GithubSyncSheetState();
}

class _GithubSyncSheetState extends State<_GithubSyncSheet> {
  late final TextEditingController _token;
  late final TextEditingController _owner;
  late final TextEditingController _repo;
  late final TextEditingController _path;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _token = TextEditingController(text: widget.initial.token);
    _owner = TextEditingController(text: widget.initial.owner);
    _repo = TextEditingController(text: widget.initial.repo);
    _path = TextEditingController(text: widget.initial.path);
  }

  @override
  void dispose() {
    _token.dispose();
    _owner.dispose();
    _repo.dispose();
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A3A42),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Đồng bộ GitHub JSON',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Lưu scans vào data/scans.json trên repo cá nhân. '
              'Dùng Personal Access Token (contents: write). '
              'Token chỉ lưu trên máy bạn — không commit lên git.',
              style: TextStyle(color: colors.muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _token,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'GitHub PAT',
                hintText: 'github_pat_…',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _owner,
              decoration: const InputDecoration(labelText: 'Owner'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _repo,
              decoration: const InputDecoration(labelText: 'Repo'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _path,
              decoration: const InputDecoration(
                labelText: 'Path JSON',
                hintText: 'data/scans.json',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  GithubSyncConfig(
                    owner: _owner.text.trim().isEmpty
                        ? GithubScanSync.defaultOwner
                        : _owner.text.trim(),
                    repo: _repo.text.trim().isEmpty
                        ? GithubScanSync.defaultRepo
                        : _repo.text.trim(),
                    path: _path.text.trim().isEmpty
                        ? GithubScanSync.defaultPath
                        : _path.text.trim(),
                    token: _token.text.trim(),
                  ),
                );
              },
              child: const Text('Lưu cấu hình'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      ),
    );
  }
}
