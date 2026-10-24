import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../xtream/state/server_session_provider.dart';
import '../data/play_item.dart';
import 'player_screen.dart';

/// Abre o player já ligado ao progresso do servidor atual.
Future<void> launchPlayer(
  BuildContext context,
  List<PlayItem> items, {
  int index = 0,
}) {
  final provider = context.read<ServerSessionProvider>();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        items: items,
        initialIndex: index,
        onProgress: provider.recordProgress,
      ),
    ),
  );
}
