import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/focus_ring.dart';
import '../../player/ui/play_launcher.dart';
import '../../version/state/version_provider.dart';
import '../../xtream/data/xtream_models.dart';
import '../../xtream/state/server_session_provider.dart';
import '../../xtream/ui/live_view.dart';

/// Início do servidor (mockup "Home"): destaque, continuar assistindo e canais.
class HomeView extends StatefulWidget {
  const HomeView({super.key, required this.onOpenLive});

  /// Leva à aba "Ao vivo" (usado quando ainda não há nada para continuar).
  final VoidCallback onOpenLive;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  String? _liveCategoryId;
  bool _updateDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<ServerSessionProvider>();
      p.loadContinue();
      p.loadCategories(XtreamSection.live);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerSessionProvider>();

    // Fileira de canais: primeira categoria ao vivo.
    final cats = provider.section(XtreamSection.live).items;
    if (cats != null && cats.isNotEmpty && _liveCategoryId != cats.first.id) {
      _liveCategoryId = cats.first.id;
      final id = cats.first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) provider.loadChannels(id);
      });
    }
    final channels = _liveCategoryId == null
        ? null
        : provider.channels(_liveCategoryId!).items;
    final continueList = provider.continueWatching;

    final version = context.watch<VersionProvider>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        if (version.updateAvailable && !_updateDismissed)
          _UpdateBanner(
            latest: version.info.latest,
            current: version.current,
            url: version.info.updateUrl,
            onDismiss: () => setState(() => _updateDismissed = true),
          ),
        _Hero(
          entry: continueList.isEmpty ? null : continueList.first,
          onPlay: (entry) => launchPlayer(context, [entry.item]),
          onOpenLive: widget.onOpenLive,
        ),
        if (continueList.isNotEmpty) ...[
          const _SectionTitle('Continuar assistindo'),
          SizedBox(
            height: 176,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: continueList.length,
              itemBuilder: (context, i) => _WideCard(
                entry: continueList[i],
                onTap: () => launchPlayer(context, [continueList[i].item]),
              ),
            ),
          ),
        ],
        if (channels != null && channels.isNotEmpty) ...[
          const _SectionTitle('Canais ao vivo'),
          SizedBox(
            height: 96,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: channels.length > 12 ? 12 : channels.length,
              itemBuilder: (context, i) => _ChannelCard(
                channel: channels[i],
                onTap: () => launchPlayer(
                  context,
                  [for (final c in channels) provider.channelItem(c)],
                  index: i,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.entry, required this.onPlay, required this.onOpenLive});

  final ContinueEntry? entry;
  final ValueChanged<ContinueEntry> onPlay;
  final VoidCallback onOpenLive;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B3A67), Color(0xFF14182B), Color(0xFF0B0C12)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.circle, size: 10, color: AppColors.accent),
              const SizedBox(width: 10),
              Text(
                e == null ? 'BEM-VINDO' : 'CONTINUAR ASSISTINDO',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            e?.item.title ?? 'Escolha o que assistir',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.1),
          ),
          const SizedBox(height: 10),
          Text(
            e == null
                ? 'Canais ao vivo, filmes e séries do seu servidor.'
                : 'Parou em ${formatDuration(e.position)} de ${formatDuration(e.duration)}',
            style: const TextStyle(fontSize: 16, color: AppColors.textMuted),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            autofocus: true,
            style: focusRingStyle(),
            icon: Icon(e == null ? Icons.live_tv : Icons.play_arrow),
            label: Text(e == null ? 'Ver canais ao vivo' : 'Continuar'),
            onPressed: e == null ? onOpenLive : () => onPlay(e),
          ),
        ],
      ),
    );
  }
}

class _WideCard extends StatefulWidget {
  const _WideCard({required this.entry, required this.onTap});

  final ContinueEntry entry;
  final VoidCallback onTap;

  @override
  State<_WideCard> createState() => _WideCardState();
}

class _WideCardState extends State<_WideCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final image = e.item.imageUrl;
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) ensureVisibleOnFocus(context);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 280,
          height: 158,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 3,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                Image.network(image, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 28, 12, 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Text(
                    e.item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: e.fraction,
                  minHeight: 5,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelCard extends StatefulWidget {
  const _ChannelCard({required this.channel, required this.onTap});

  final XtreamChannel channel;
  final VoidCallback onTap;

  @override
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) ensureVisibleOnFocus(context);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 260,
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focused ? Colors.white : AppColors.border,
              width: _focused ? 3 : 2,
            ),
          ),
          child: Row(
            children: [
              ChannelLogo(url: widget.channel.iconUrl, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: AppColors.live),
                        SizedBox(width: 6),
                        Text('AO VIVO',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.live)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aviso (não bloqueia) de que existe uma versão mais nova do aplicativo.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({
    required this.latest,
    required this.current,
    required this.url,
    required this.onDismiss,
  });

  final String latest;
  final String current;
  final String url;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Nova versão $latest disponível (você tem $current).'
              '${url.isEmpty ? ' Fale com o administrador.' : '  Baixe em: $url'}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(style: focusRingStyle(), onPressed: onDismiss, child: const Text('Depois')),
        ],
      ),
    );
  }
}
