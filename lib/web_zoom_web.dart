import 'package:web/web.dart';

/// Zoom kỹ thuật số trên preview video (CSS scale + crop).
Future<void> applyWebDigitalZoom(double scale) async {
  final clamped = scale.clamp(1.0, 4.0);
  final videos = document.querySelectorAll('video');
  for (var i = 0; i < videos.length; i++) {
    final node = videos.item(i);
    if (node == null) continue;
    final video = node as HTMLVideoElement;
    if (clamped <= 1.01) {
      video.style.transform = '';
      video.style.transformOrigin = 'center';
      continue;
    }
    video.style.transformOrigin = 'center';
    video.style.transform = 'scale($clamped)';
  }
}
