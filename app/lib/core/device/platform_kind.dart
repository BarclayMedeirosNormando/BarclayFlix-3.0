import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';

/// Plataforma como a API v1 a conhece.
enum AppPlatform {
  android('android'),
  androidTv('android_tv'),
  windows('windows'),
  unsupported('unknown');

  const AppPlatform(this.apiName);
  final String apiName;
}

/// Detecta Windows, Android (toque) e Android TV (recurso `leanback`).
Future<AppPlatform> detectPlatform() async {
  if (Platform.isWindows) return AppPlatform.windows;
  if (Platform.isAndroid) {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final isTv = info.systemFeatures.contains('android.software.leanback');
      return isTv ? AppPlatform.androidTv : AppPlatform.android;
    } on Exception {
      return AppPlatform.android;
    }
  }
  return AppPlatform.unsupported;
}
