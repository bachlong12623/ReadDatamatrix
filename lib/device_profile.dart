import 'package:flutter/foundation.dart';

import 'device_profile_stub.dart'
    if (dart.library.js_interop) 'device_profile_web.dart' as impl;

/// Nhận diện thiết bị/trình duyệt để tinh chỉnh camera quét.
class DeviceProfile {
  const DeviceProfile({
    required this.isWeb,
    required this.isAppleMobileWeb,
    required this.isIphone,
  });

  final bool isWeb;
  final bool isAppleMobileWeb;
  final bool isIphone;

  /// Safari/WebKit trên iPhone/iPad (Chrome iOS cũng dùng WebKit).
  bool get isIosSafariFamily => isAppleMobileWeb;

  static DeviceProfile detect() {
    if (!kIsWeb) {
      return const DeviceProfile(
        isWeb: false,
        isAppleMobileWeb: false,
        isIphone: false,
      );
    }
    return impl.detectWebDeviceProfile();
  }
}
