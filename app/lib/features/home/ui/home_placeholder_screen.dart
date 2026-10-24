import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/data/device_models.dart';
import '../../auth/state/auth_provider.dart';

/// Placeholder pós-ativação. Será substituído pela home real (catálogo).
/// Não exibe usuário/senha dos servidores.
class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final device = context.watch<AuthProvider>().device;
    final theme = Theme.of(context);
    final expira = device?.expiraEm;

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
                  Text(
                    'Dispositivo ativo',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  if (device?.clienteNome case final nome? when nome.isNotEmpty)
                    Text('Cliente: $nome'),
                  if (expira != null) Text('Vence em: ${_fmt(expira)}'),
                  const SizedBox(height: 16),
                  Text('Servidores', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final s in device?.servers ?? const <XtreamServer>[])
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.dns),
                      title: Text(s.apelido),
                      subtitle: Text(s.hosts.join('  •  ')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
