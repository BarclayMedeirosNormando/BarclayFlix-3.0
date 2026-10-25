import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/telemetry/telemetry.dart';
import '../../xtream/state/server_session_provider.dart';
import '../data/play_item.dart';
import 'player_screen.dart';

/// Abre o player já ligado ao progresso, à programação (EPG) e ao monitor do servidor atual.
Future<void> launchPlayer(
  BuildContext context,
  List<PlayItem> items, {
  int index = 0,
}) {
  final provider = context.read<ServerSessionProvider>();
  TelemetryApi telemetry;
  try {
    telemetry = context.read<TelemetryApi>();
  } on ProviderNotFoundException {
    telemetry = const NullTelemetry();
  }
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        items: items,
        initialIndex: index,
        onProgress: provider.recordProgress,
        epgLoader: provider.epgFor,
        telemetry: telemetry,
        serverId: provider.server.id,
      ),
    ),
  );
}
