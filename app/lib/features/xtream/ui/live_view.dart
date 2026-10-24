import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/focus_tile.dart';
import '../../player/ui/player_screen.dart';
import '../data/xtream_models.dart';
import '../state/server_session_provider.dart';

/// Aba "Ao vivo" no layout do mockup: categorias | canais | painel do canal.
///
/// O painel da direita mostra só o nome/logo do canal em foco: abrir um
/// segundo stream para "prévia" estouraria o limite de conexões do plano.
class LiveView extends StatefulWidget {
  const LiveView({super.key, required this.categories});

  final List<XtreamCategory> categories;

  @override
  State<LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends State<LiveView> {
  late XtreamCategory _category = widget.categories.first;
  XtreamChannel? _focusedChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ServerSessionProvider>().loadChannels(_category.id);
      }
    });
  }

  void _select(XtreamCategory c) {
    setState(() {
      _category = c;
      _focusedChannel = null;
    });
    context.read<ServerSessionProvider>().loadChannels(c.id);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerSessionProvider>();
    final state = provider.channels(_category.id);

    return LayoutBuilder(builder: (context, box) {
      // Telas estreitas (celular, janela pequena) escondem o painel lateral.
      final showInfo = box.maxWidth >= 1000;
      final categoriesWidth = box.maxWidth >= 700 ? 300.0 : 160.0;
      return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: categoriesWidth,
            child: _Column(
              title: 'CATEGORIAS',
              child: ListView.builder(
                itemCount: widget.categories.length,
                itemBuilder: (context, i) {
                  final c = widget.categories[i];
                  return FocusTile(
                    autofocus: i == 0,
                    selected: c.id == _category.id,
                    onTap: () => _select(c),
                    child: Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: _Column(
              title: 'CANAIS · ${_category.name.toUpperCase()}',
              child: _channels(provider, state),
            ),
          ),
          if (showInfo) ...[
            const SizedBox(width: 24),
            SizedBox(
              width: 280,
              child: _InfoPanel(channel: _focusedChannel, category: _category),
            ),
          ],
        ],
      ),
    );
    });
  }

  Widget _channels(ServerSessionProvider provider, ChannelsState state) {
    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => provider.loadChannels(_category.id, force: true),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }
    final channels = state.items;
    if (channels == null) return const Center(child: CircularProgressIndicator());
    if (channels.isEmpty) return const Center(child: Text('Nenhum canal nesta categoria.'));

    return ListView.builder(
      itemCount: channels.length,
      itemBuilder: (context, i) {
        final ch = channels[i];
        return FocusTile(
          onFocus: () => setState(() => _focusedChannel = ch),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => PlayerScreen(
              channels: channels,
              initialIndex: i,
              session: provider.session!,
            ),
          )),
          child: Row(
            children: [
              ChannelLogo(url: ch.iconUrl, size: 44),
              const SizedBox(width: 12),
              SizedBox(
                width: 36,
                child: Text(
                  '${ch.number ?? i + 1}',
                  style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: Text(
                  ch.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.5,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.channel, required this.category});

  final XtreamChannel? channel;
  final XtreamCategory category;

  @override
  Widget build(BuildContext context) {
    final ch = channel;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: ch == null
          ? const Text(
              'Use as setas para escolher um canal e OK para assistir.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 16),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ChannelLogo(url: ch.iconUrl, size: 96),
                const SizedBox(height: 16),
                Text(ch.name,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(category.name, style: const TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: AppColors.live),
                    SizedBox(width: 8),
                    Text('AO VIVO',
                        style: TextStyle(
                            color: AppColors.live, fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Logo do canal com ícone genérico quando falta ou falha o carregamento.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({super.key, this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.live_tv, size: size * 0.5),
    );
    final u = url;
    if (u == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        u,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
