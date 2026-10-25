import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/device/device_profile.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/device_models.dart';
import '../../auth/state/auth_provider.dart';
import '../../favorites/data/favorites_repository.dart';
import '../../progress/data/progress_repository.dart';
import '../../settings/ui/settings_view.dart';
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
    final compact = DeviceProfile.of(context).compact;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: compact
              ? const EdgeInsets.fromLTRB(20, 12, 20, 16)
              : const EdgeInsets.fromLTRB(40, 24, 40, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(TextSpan(
                    style: TextStyle(fontSize: compact ? 24 : 28, fontWeight: FontWeight.w800),
                    children: [
                      TextSpan(text: 'Barclay'),
                      TextSpan(text: 'Flix', style: TextStyle(color: AppColors.accent)),
                    ],
                  )),
                  IconButton(
                    tooltip: 'Configurações',
                    icon: const Icon(Icons.settings),
                    style: ButtonStyle(
                      side: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.focused)
                            ? const BorderSide(color: Colors.white, width: 2)
                            : null,
                      ),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Dispositivo ativo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.accent, fontWeight: FontWeight.w700)),
                        if (device?.clienteNome case final nome? when nome.isNotEmpty)
                          Text('Cliente: $nome',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (expira != null)
                          Text('Vence em: ${formatDate(expira)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 24 : 56),
              Text('Escolha o servidor',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800, fontSize: compact ? 30 : null)),
              const SizedBox(height: 8),
              Text('Selecione onde você quer assistir agora.',
                  style: TextStyle(
                      fontSize: compact ? 16 : 18, color: AppColors.textMuted)),
              SizedBox(height: compact ? 20 : 40),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    // Celular: 2 cartões por linha ocupando a largura; demais: 280x180.
                    final gap = compact ? 14.0 : 24.0;
                    final w = compact ? (box.maxWidth - gap) / 2 : 280.0;
                    final h = compact ? 118.0 : 180.0;
                    return SingleChildScrollView(
                      child: Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final (i, s) in servers.indexed)
                            _ServerCard(
                              name: s.apelido,
                              width: w,
                              height: h,
                              compact: compact,
                              autofocus: i == 0,
                              onTap: () => _open(context, s),
                            ),
                        ],
                      ),
                    );
                  },
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
    final progress = context.read<ProgressApi>();
    final favorites = context.read<FavoritesApi>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => ServerSessionProvider(
            api,
            server,
            progress: progress,
            favorites: favorites,
          )..connect(),
          child: const ServerScreen(),
        ),
      ),
    );
  }
}

class _ServerCard extends StatefulWidget {
  const _ServerCard({
    required this.name,
    required this.onTap,
    required this.width,
    required this.height,
    required this.compact,
    this.autofocus = false,
  });

  final String name;
  final double width;
  final double height;
  final bool compact;
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
        width: widget.width,
        height: widget.height,
        padding: EdgeInsets.all(widget.compact ? 16 : 24),
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
              width: widget.compact ? 44 : 56,
              height: widget.compact ? 44 : 56,
              decoration: BoxDecoration(
                color: const Color(0xFF1B2442),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.dns_outlined, size: widget.compact ? 24 : 28),
            ),
            Text(
              widget.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: widget.compact ? 20 : 26, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
