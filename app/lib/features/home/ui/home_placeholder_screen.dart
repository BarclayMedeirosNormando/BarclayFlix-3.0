import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/device_models.dart';
import '../../auth/state/auth_provider.dart';
import '../../xtream/data/xtream_client.dart';
import '../../xtream/state/server_session_provider.dart';
import '../../xtream/ui/server_screen.dart';

/// Escolha do servidor pós-ativação (mockup "Escolha do servidor").
/// Será substituída pela home real. Não exibe usuário/senha nem endereços.
class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final device = context.watch<AuthProvider>().device;
    final expira = device?.expiraEm;
    final servers = device?.servers ?? const <XtreamServer>[];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text.rich(TextSpan(
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                    children: [
                      TextSpan(text: 'Barclay'),
                      TextSpan(text: 'Flix', style: TextStyle(color: AppColors.accent)),
                    ],
                  )),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Dispositivo ativo',
                          style: TextStyle(
                              color: AppColors.accent, fontWeight: FontWeight.w700)),
                      if (device?.clienteNome case final nome? when nome.isNotEmpty)
                        Text('Cliente: $nome',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (expira != null)
                        Text('Vence em: ${formatDate(expira)}',
                            style: const TextStyle(color: AppColors.textMuted)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 56),
              Text('Escolha o servidor',
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Selecione onde você quer assistir agora.',
                  style: TextStyle(fontSize: 18, color: AppColors.textMuted)),
              const SizedBox(height: 40),
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    children: [
                      for (final (i, s) in servers.indexed)
                        _ServerCard(
                          name: s.apelido,
                          autofocus: i == 0,
                          onTap: () => _open(context, s),
                        ),
                    ],
                  ),
                ),
              ),
            ],
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

class _ServerCard extends StatefulWidget {
  const _ServerCard({required this.name, required this.onTap, this.autofocus = false});

  final String name;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(24),
      onTap: widget.onTap,
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 280,
        height: 180,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _focused ? Colors.white : AppColors.border,
            width: _focused ? 3 : 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF1B2442),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.dns_outlined, size: 28),
            ),
            Text(
              widget.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
