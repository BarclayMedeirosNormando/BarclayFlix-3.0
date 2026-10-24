import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../auth/data/device_models.dart';
import '../../auth/state/auth_provider.dart';
import '../../xtream/data/xtream_client.dart';
import '../../xtream/state/server_session_provider.dart';
import '../../xtream/ui/server_screen.dart';

/// Placeholder pós-ativação: lista os servidores e abre o escolhido.
/// Será substituído pela home real. Não exibe usuário/senha nem endereços.
class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final device = context.watch<AuthProvider>().device;
    final theme = Theme.of(context);
    final expira = device?.expiraEm;
    final servers = device?.servers ?? const <XtreamServer>[];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dispositivo ativo', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  if (device?.clienteNome case final nome? when nome.isNotEmpty)
                    Text('Cliente: $nome'),
                  if (expira != null) Text('Vence em: ${formatDate(expira)}'),
                  const SizedBox(height: 16),
                  Text('Servidores', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final (i, s) in servers.indexed)
                    ListTile(
                      autofocus: i == 0,
                      dense: true,
                      leading: const Icon(Icons.dns),
                      title: Text(s.apelido),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(context, s),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, XtreamServer server) {
    final api = context.read<XtreamApi>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => ServerSessionProvider(api, server)..connect(),
          child: const ServerScreen(),
        ),
      ),
    );
  }
}
