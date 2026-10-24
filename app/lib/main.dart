import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/device/device_identity.dart';
import 'core/device/platform_kind.dart';
import 'core/network/api_client.dart';
import 'core/ui/config_error_app.dart';
import 'features/auth/data/auth_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Falha alto: sem API_URL válida, mostra erro claro em vez de seguir.
  final config = AppConfig.fromEnvironment();
  final problem = config.problem;
  if (problem != null) {
    runApp(ConfigErrorApp(problem: problem));
    return;
  }

  MediaKit.ensureInitialized();

  final info = await PackageInfo.fromPlatform();
  final platform = await detectPlatform();
  final api = ApiClient(baseUrl: config.apiUrl.trim(), appVersion: info.version);

  runApp(BarclayFlixApp(
    checker: AuthRepository(api, DeviceIdentity(), platform),
  ));
}
