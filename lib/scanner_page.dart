import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'app_theme.dart';
import 'barcode_payload.dart';
import 'device_profile.dart';
import 'ios_camera_tune.dart';
import 'scan_export.dart';
import 'scan_store.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  static const _dedupeWindow = Duration(milliseconds: 800);
  static const _hitHold = Duration(seconds: 2);
  static const _accentGreen = Color(0xFF2EE6A6);

  late final DeviceProfile _profile;
  late final ScanStore _store;
  late final ScanExporter _exporter;
  late MobileScannerController _controller;
  bool _ready = false;
  bool _invertImage = false;
  bool _closeRangeApplied = false;
  bool _rebuildingController = false;
  bool _iosCameraTuned = false;

  String? _latestResult;
  DateTime? _latestAt;
  String? _lastAccepted;
  DateTime? _lastAcceptedAt;
  final List<ScanRecord> _history = [];

  List<Offset> _hitCorners = const [];
  Size _hitBarcodeSize = Size.zero;
  Size _hitCameraSize = Size.zero;
  Timer? _hitTimer;

  @override
  void initState() {
    super.initState();
    _profile = DeviceProfile.detect();
    _exporter = const ScanExporter();
    _controller = _createController(invertImage: false);
    _controller.addListener(_onControllerState);
    unawaited(_initStore());
  }

  Future<void> _initStore() async {
    _store = await ScanStore.open();
    final saved = _store.load();
    if (!mounted) return;
    setState(() {
      _history
        ..clear()
        ..addAll(saved);
      if (saved.isNotEmpty) {
        _latestResult = saved.first.text;
        _latestAt = saved.first.at;
      }
      _ready = true;
    });
  }

  Future<void> _persistHistory() async {
    if (!_ready) return;
    await _store.save(_history);
  }

  MobileScannerController _createController({required bool invertImage}) {
    final iosWeb = _profile.isIosSafariFamily;

    return MobileScannerController(
      facing: CameraFacing.back,
      // iPhone Safari: WASM nặng — interval ~100ms ổn định hơn unrestricted.
      detectionSpeed: iosWeb ? DetectionSpeed.normal : DetectionSpeed.unrestricted,
      detectionTimeoutMs: iosWeb ? 100 : 250,
      formats: const [BarcodeFormat.dataMatrix],
      // Web/iPhone Air: yêu cầu 1080p (Fusion Main xử lý tốt, WASM vẫn kịp).
      cameraResolution: const Size(1920, 1080),
      autoZoom: false,
      invertImage: invertImage && !kIsWeb,
    );
  }

  void _onControllerState() {
    if (!_controller.value.isRunning) return;

    if (_profile.isIosSafariFamily && !_iosCameraTuned) {
      _iosCameraTuned = true;
      unawaited(_tuneIosCamera());
    }

    if (_closeRangeApplied) return;
    _closeRangeApplied = true;
    unawaited(_preferCloseRangeLens());
  }

  Future<void> _tuneIosCamera() async {
    // Đợi video gắn vào DOM rồi khóa zoom/playsinline.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await tuneIosSafariCamera();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await tuneIosSafariCamera();
  }

  Future<void> _preferCloseRangeLens() async {
    if (kIsWeb) return;
    try {
      final facing = _controller.value.cameraDirection;
      if (facing == CameraFacing.unknown || facing == CameraFacing.external) {
        return;
      }
      final best = await _controller.getBestCloseRangeScanningLens(
        facing: facing,
      );
      final supported = await _controller.getSupportedLenses(facing: facing);
      if (best == null || !supported.contains(best)) return;
      if (best == _controller.value.cameraLensType) return;
      await _controller.switchCamera(
        SelectCamera(facingDirection: facing, lensType: best),
      );
    } catch (_) {
      // Không phải mọi thiết bị hỗ trợ đổi lens.
    }
  }

  Future<void> _rebuildController({required bool invertImage}) async {
    if (_rebuildingController) return;
    _rebuildingController = true;
    setState(() {
      _invertImage = invertImage;
      _closeRangeApplied = false;
      _iosCameraTuned = false;
    });

    final old = _controller;
    old.removeListener(_onControllerState);
    final next = _createController(invertImage: invertImage);
    next.addListener(_onControllerState);

    setState(() => _controller = next);
    await old.dispose();
    _rebuildingController = false;
  }

  @override
  void dispose() {
    _hitTimer?.cancel();
    _controller.removeListener(_onControllerState);
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      if (barcode.format != BarcodeFormat.dataMatrix &&
          barcode.format != BarcodeFormat.unknown) {
        continue;
      }

      final value = extractBarcodePayload(barcode);
      if (value == null || value.isEmpty) continue;

      final now = DateTime.now();
      final isDupe = _lastAccepted == value &&
          _lastAcceptedAt != null &&
          now.difference(_lastAcceptedAt!) < _dedupeWindow;

      // Luôn cập nhật viền xanh quanh mã đang thấy.
      _showHit(
        corners: barcode.corners,
        barcodeSize: barcode.size,
        cameraSize: capture.size,
      );

      if (isDupe) return;

      _lastAccepted = value;
      _lastAcceptedAt = now;

      setState(() {
        _latestResult = value;
        _latestAt = now;
        _history.removeWhere((e) => e.text == value);
        _history.insert(0, ScanRecord(text: value, at: now));
        if (_history.length > ScanStore.maxRecords) {
          _history.removeRange(ScanStore.maxRecords, _history.length);
        }
      });

      unawaited(_persistHistory());
      HapticFeedback.mediumImpact();
      return;
    }
  }

  void _showHit({
    required List<Offset> corners,
    required Size barcodeSize,
    required Size cameraSize,
  }) {
    if (corners.isEmpty || cameraSize.isEmpty) return;
    _hitTimer?.cancel();
    setState(() {
      _hitCorners = List<Offset>.from(corners);
      _hitBarcodeSize = barcodeSize;
      _hitCameraSize = cameraSize;
    });
    _hitTimer = Timer(_hitHold, () {
      if (!mounted) return;
      setState(() => _hitCorners = const []);
    });
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đèn flash không khả dụng trên thiết bị này.'),
        ),
      );
    }
  }

  Future<void> _switchCamera() async {
    try {
      _closeRangeApplied = false;
      await _controller.switchCamera();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể đổi camera.')),
      );
    }
  }

  Future<void> _toggleInvert() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đảo màu chỉ hỗ trợ trên Android. Trên web hãy thử xoay/đưa mã gần hơn.',
          ),
        ),
      );
      return;
    }
    await _rebuildController(invertImage: !_invertImage);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _invertImage
              ? 'Đã bật đảo màu (mã sáng trên nền tối).'
              : 'Đã tắt đảo màu.',
        ),
      ),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã sao chép kết quả.')),
    );
  }

  Future<void> _exportHistory(ExportFormat format) async {
    if (_history.isEmpty) return;
    try {
      await _exporter.exportAndShare(_history, format: format);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Đã tải file — trên iPhone chọn Lưu vào Files / iCloud.'
                : 'Mở share sheet — gửi AirDrop / lưu Files.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không xuất được file: $e')),
      );
    }
  }

  Future<void> _clearHistory() async {
    setState(() {
      _history.clear();
      _latestResult = null;
      _latestAt = null;
      _hitCorners = const [];
    });
    if (_ready) await _store.clear();
  }

  void _clearLatest() {
    setState(() {
      _latestResult = null;
      _latestAt = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final wide = size.width >= 900;
    final iphone = _profile.isIphone;

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          padding.top + 8,
          16,
          padding.bottom + 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              invertActive: _invertImage,
              onTorch: _toggleTorch,
              onSwitchCamera: _switchCamera,
              onInvert: _toggleInvert,
              subtitle: iphone
                  ? 'iPhone Air · Safari · camera sau 1×'
                  : 'Vuông · chữ nhật · đảo màu',
            ),
            const SizedBox(height: 10),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: _buildPreview(colors)),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: _buildSidePanel(colors)),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(
                          flex: iphone ? 7 : 5,
                          child: _buildPreview(colors),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          flex: iphone ? 3 : 4,
                          child: _buildSidePanel(colors),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(AppColors colors) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: colors.surface),
          MobileScanner(
            key: ValueKey(
              'scanner-invert-$_invertImage-${identityHashCode(_controller)}',
            ),
            controller: _controller,
            fit: BoxFit.cover,
            tapToFocus: _profile.isIosSafariFamily || !kIsWeb,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return _CameraMessage(
                title: 'Không mở được camera',
                message: _friendlyError(error),
                onRetry: () {
                  _iosCameraTuned = false;
                  unawaited(_controller.start());
                },
              );
            },
          ),
          // Viền xanh realtime quanh mã đang detect.
          IgnorePointer(
            child: BarcodeOverlay(
              controller: _controller,
              boxFit: BoxFit.cover,
              color: _accentGreen.withValues(alpha: 0.85),
              style: PaintingStyle.stroke,
            ),
          ),
          // Giữ viền ~2s sau khi đọc thành công để xác nhận mã nào.
          if (_hitCorners.isNotEmpty)
            IgnorePointer(
              child: CustomPaint(
                painter: _HitBorderPainter(
                  corners: _hitCorners,
                  barcodeSize: _hitBarcodeSize,
                  cameraSize: _hitCameraSize,
                  color: _accentGreen,
                ),
              ),
            ),
          const IgnorePointer(child: _ScanOverlay()),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Text(
              _invertImage
                  ? 'Chế độ đảo màu · mã trắng trên nền đen'
                  : _profile.isIphone
                      ? 'Giữ ~15–25 cm · camera sau 1× · chạm để lấy nét'
                      : 'Vuông / chữ nhật · thường / đảo màu đều được',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
                fontSize: 13,
                shadows: const [
                  Shadow(blurRadius: 8, color: Colors.black54),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _friendlyError(MobileScannerException error) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Cần quyền camera để quét mã Data Matrix.',
      MobileScannerErrorCode.unsupported =>
        'Thiết bị hoặc trình duyệt không hỗ trợ camera.',
      _ => error.errorCode.message,
    };
  }

  Widget _buildSidePanel(AppColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A3A42)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Kết quả',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _latestAt == null
                  ? 'Chưa có mã nào được đọc'
                  : 'Lúc ${_formatTime(_latestAt!)}',
              style: TextStyle(color: colors.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1215),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2A3A42)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _latestResult ?? '—',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 14,
                        height: 1.45,
                        color: _latestResult == null
                            ? colors.muted
                            : const Color(0xFFE8F1F4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _latestResult == null
                        ? null
                        : () => _copy(_latestResult!),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Sao chép'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _latestResult == null ? null : _clearLatest,
                  child: const Text('Xóa'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed:
                        !_ready || _history.isEmpty
                            ? null
                            : () => _exportHistory(ExportFormat.csv),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      kIsWeb ? 'Tải CSV' : 'Xuất CSV',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        !_ready || _history.isEmpty
                            ? null
                            : () => _exportHistory(ExportFormat.txt),
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('TXT', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Xóa toàn bộ lịch sử tạm',
                  onPressed: !_ready || _history.isEmpty ? null : _clearHistory,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Lưu tạm trên máy · xuất CSV rồi mở trên máy tính (Files/iCloud)',
              style: TextStyle(color: colors.muted, fontSize: 11),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Lịch sử',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_history.length}/${ScanStore.maxRecords}',
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: !_ready
                  ? Text(
                      'Đang tải lịch sử tạm…',
                      style: TextStyle(color: colors.muted, fontSize: 13),
                    )
                  : _history.isEmpty
                      ? Text(
                          'Quét mã trên điện thoại — xuất CSV để lấy trên máy tính.',
                          style: TextStyle(color: colors.muted, fontSize: 13),
                        )
                      : ListView.separated(
                          itemCount: _history.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _history[index];
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                setState(() {
                                  _latestResult = item.text;
                                  _latestAt = item.at;
                                });
                              },
                              onLongPress: () => _copy(item.text),
                              child: Ink(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFF2A3A42),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.text,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 12,
                                        height: 1.35,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatTime(item.at),
                                      style: TextStyle(
                                        color: colors.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.invertActive,
    required this.onTorch,
    required this.onSwitchCamera,
    required this.onInvert,
    this.subtitle = 'Vuông · chữ nhật · đảo màu',
  });

  final bool invertActive;
  final VoidCallback onTorch;
  final VoidCallback onSwitchCamera;
  final VoidCallback onInvert;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: colors.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colors.accent.withValues(alpha: 0.45),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DataMatrix Reader',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  height: 1.1,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Đảo màu (Android)',
          onPressed: onInvert,
          style: IconButton.styleFrom(
            backgroundColor: invertActive
                ? colors.accent.withValues(alpha: 0.22)
                : const Color(0xFF1A2A32),
            foregroundColor: invertActive
                ? colors.accent
                : const Color(0xFFE8F1F4),
          ),
          icon: const Icon(Icons.invert_colors_rounded),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Đèn flash',
          onPressed: onTorch,
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF1A2A32),
            foregroundColor: colors.accent,
          ),
          icon: const Icon(Icons.flash_on_rounded),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Đổi camera',
          onPressed: onSwitchCamera,
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF1A2A32),
            foregroundColor: const Color(0xFFE8F1F4),
          ),
          icon: const Icon(Icons.cameraswitch_rounded),
        ),
      ],
    );
  }
}

class _HitBorderPainter extends CustomPainter {
  const _HitBorderPainter({
    required this.corners,
    required this.barcodeSize,
    required this.cameraSize,
    required this.color,
  });

  final List<Offset> corners;
  final Size barcodeSize;
  final Size cameraSize;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 4 || cameraSize.isEmpty) return;

    // BoxFit.cover mapping từ toạ độ camera → widget.
    final scale = math.max(
      size.width / cameraSize.width,
      size.height / cameraSize.height,
    );
    final dx = (size.width - cameraSize.width * scale) / 2;
    final dy = (size.height - cameraSize.height * scale) / 2;

    final path = Path();
    for (var i = 0; i < corners.length; i++) {
      final p = Offset(
        corners[i].dx * scale + dx,
        corners[i].dy * scale + dy,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();

    final fill = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _HitBorderPainter oldDelegate) {
    return oldDelegate.corners != corners ||
        oldDelegate.cameraSize != cameraSize ||
        oldDelegate.color != color;
  }
}

class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ReticlePainter());
  }
}

class _ReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Cửa sổ chữ nhật rộng — phù hợp Data Matrix ECC200 hình chữ nhật.
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.22);
    final stroke = Paint()
      ..color = const Color(0xFF2EE6A6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final secondary = Paint()
      ..color = const Color(0xFF2EE6A6).withValues(alpha: 0.45)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final short = size.shortestSide;
    final rectW = (size.width * 0.78).clamp(short * 0.7, size.width * 0.9);
    // Tỷ lệ ~16:10 gần các size chữ nhật phổ biến (12x26, 16x36, 16x48…).
    final rectH = (rectW / 1.65).clamp(short * 0.34, size.height * 0.55);
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: rectW,
      height: rectH,
    );

    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)));
    canvas.drawPath(path, dim..style = PaintingStyle.fill);

    // Gợi ý mã vuông ở giữa (không che vùng quét).
    final squareSide = rectH * 0.78;
    final square = Rect.fromCenter(
      center: rect.center,
      width: squareSide,
      height: squareSide,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(square, const Radius.circular(10)),
      secondary,
    );

    const corner = 26.0;
    void drawCorner(Offset a, Offset b, Offset c) {
      canvas.drawLine(a, b, stroke);
      canvas.drawLine(b, c, stroke);
    }

    drawCorner(
      Offset(rect.left, rect.top + corner),
      rect.topLeft,
      Offset(rect.left + corner, rect.top),
    );
    drawCorner(
      Offset(rect.right - corner, rect.top),
      rect.topRight,
      Offset(rect.right, rect.top + corner),
    );
    drawCorner(
      Offset(rect.left, rect.bottom - corner),
      rect.bottomLeft,
      Offset(rect.left + corner, rect.bottom),
    );
    drawCorner(
      Offset(rect.right - corner, rect.bottom),
      rect.bottomRight,
      Offset(rect.right, rect.bottom - corner),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0B1215),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8FA3AD)),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
            ],
          ),
        ),
      ),
    );
  }
}
