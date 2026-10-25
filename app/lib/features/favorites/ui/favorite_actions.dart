import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../xtream/state/server_session_provider.dart';
import '../data/favorites_repository.dart';

/// Liga/desliga o item na Minha lista e avisa com uma mensagem curta.
Future<void> toggleFavoriteWithMessage(BuildContext context, FavoriteEntry entry) async {
  final provider = context.read<ServerSessionProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final nowOn = await provider.toggleFavorite(entry);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(nowOn ? 'Adicionado à Minha lista.' : 'Removido da Minha lista.'),
    ));
}
