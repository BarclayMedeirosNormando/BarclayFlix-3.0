import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/device/device_identity.dart';
import 'core/device/device_profile.dart';
import 'core/device/platform_kind.dart';
import 'core/settings/video_settings.dart';
import 'core/telemetry/telemetry.dart';
import 'core/network/api_client.dart';
import 'core/network/dns_fallback.dart';
import 'core/ui/config_error_app.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/favorites/data/favorites_repository.dart';
import 'features/progress/data/progress_repository.dart';
import 'features/version/data/version_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Se o DNS da operadora bloquear um servidor, resolve por DNS sobre HTTPS.
  HttpOverrides.global = DnsFallbackOverrides();

  // Falha alto: sem API_URL válida, mostra erro claro em vez de seguir.
  final config = AppConfig.fromEnvironment();
  final problem = config.problem;
  if (problem != null) {
    runApp(ConfigErrorApp(problem: problem));
    return;
  }

  MediaKit.ensureInitialized();
  await VideoSettings.load();

  final info = await PackageInfo.fromPlatform();
  final platform = await detectPlatform();
  DeviceProfile.platform = platform;
  final api = ApiClient(baseUrl: config.apiUrl.trim(), appVersion: info.version);

  final identity = DeviceIdentity();

  runApp(BarclayFlixApp(
    checker: AuthRepository(api, identity, platform, snapshot: const SecureSnapshotStore()),
    progress: ProgressRepository(api, identity),
    favorites: FavoritesRepository(api, identity),
    version: VersionRepository(api, platform, info.version),
    appVersion: info.version,
    telemetry: TelemetryService(api, identity),
  ));
}
