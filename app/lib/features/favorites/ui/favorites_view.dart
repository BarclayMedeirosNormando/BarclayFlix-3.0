import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/focus_ring.dart';
import '../../player/ui/play_launcher.dart';
import '../../xtream/data/xtream_models.dart';
import '../../xtream/state/server_session_provider.dart';
import '../../xtream/ui/series_detail_screen.dart';
import '../data/favorites_repository.dart';
import 'favorite_actions.dart';

/// Aba "Minha lista": canais, filmes e séries guardados (valem para todos os
/// aparelhos do cliente). Segurar OK/tocar e segurar remove da lista.
class FavoritesView extends StatefulWidget {
  const FavoritesView({super.key});

  @override
  State<FavoritesView> createState() => _FavoritesViewState();
}

class _FavoritesViewState extends State<FavoritesView> {
  FavoriteType? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ServerSessionProvider>().loadFavorites(force: true);
    });
  }

  Future<void> _open(FavoriteEntry f) async {
    final provider = context.read<ServerSessionProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    switch (f.type) {
      case FavoriteType.live:
        // A lista de reprodução é só a dos canais favoritos (troca de canal entre eles).
        final items = [
          for (final x in provider.favorites.where((e) => e.type == FavoriteType.live))
            if (provider.favoriteChannelItem(x) case final it?) it,
        ];
        final index = provider.favorites
            .where((e) => e.type == FavoriteType.live)
            .toList()
            .indexWhere((e) => e.id == f.id);
        if (items.isNotEmpty && mounted) {
          launchPlayer(context, items, index: index < 0 ? 0 : index);
        }
      case FavoriteType.vod:
        final item = await provider.favoriteVodItem(f);
        if (!mounted) return;
        if (item == null) {
          messenger.showSnackBar(
              const SnackBar(content: Text('Não foi possível abrir este filme agora.')));
          return;
        }
        launchPlayer(context, [item]);
      case FavoriteType.series:
        navigator.push(MaterialPageRoute<void>(
          builder: (_) => ChangeNotifierProvider<ServerSessionProvider>.value(
            value: provider,
            child: SeriesDetailScreen(
              series: XtreamSeries(id: f.id, name: f.name, coverUrl: f.imageUrl),
            ),
          ),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerSessionProvider>();
    final all = provider.favorites;
    final list = [
      for (final f in all)
        if (_filter == null || f.type == _filter) f,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            children: [
              _FilterChip(
                label: 'Tudo',
                selected: _filter == null,
                onTap: () => setState(() => _filter = null),
              ),
              _FilterChip(
                label: 'Canais',
                selected: _filter == FavoriteType.live,
                onTap: () => setState(() => _filter = FavoriteType.live),
              ),
              _FilterChip(
                label: 'Filmes',
                selected: _filter == FavoriteType.vod,
                onTap: () => setState(() => _filter = FavoriteType.vod),
              ),
              _FilterChip(
                label: 'Séries',
                selected: _filter == FavoriteType.series,
                onTap: () => setState(() => _filter = FavoriteType.series),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      provider.favoritesLoaded
                          ? 'Sua lista está vazia.\nSegure OK (ou toque e segure) em um canal, filme ou série para guardar aqui.'
                          : 'Carregando…',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 16),
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisExtent: 320,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _FavoriteCard(
                    entry: list[i],
                    autofocus: i == 0,
                    onTap: () => _open(list[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatefulWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: widget.onTap,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) ensureVisibleOnFocus(context);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.selected ? AppColors.accent : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _focused ? Colors.white : Colors.white.withValues(alpha: 0.14),
              width: _focused ? 3 : 2,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: widget.selected ? AppColors.onAccent : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteCard extends StatefulWidget {
  const _FavoriteCard({required this.entry, required this.onTap, this.autofocus = false});

  final FavoriteEntry entry;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_FavoriteCard> createState() => _FavoriteCardState();
}

class _FavoriteCardState extends State<_FavoriteCard> {
  bool _focused = false;

  static String _label(FavoriteType t) => switch (t) {
        FavoriteType.live => 'Canal',
        FavoriteType.vod => 'Filme',
        FavoriteType.series => 'Série',
      };

  @override
  Widget build(BuildContext context) {
    final f = widget.entry;
    final fallbackIcon = f.type == FavoriteType.live ? Icons.live_tv : Icons.movie_outlined;
    return InkWell(
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(14),
      onTap: widget.onTap,
      onLongPress: () => toggleFavoriteWithMessage(context, f),
      onFocusChange: (v) {
        setState(() => _focused = v);
        if (v) ensureVisibleOnFocus(context);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _focused ? Colors.white : Colors.transparent,
                  width: 3,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: f.imageUrl == null
                  ? Center(child: Icon(fallbackIcon, size: 40, color: AppColors.textMuted))
                  : Image.network(
                      f.imageUrl!,
                      fit: f.type == FavoriteType.live ? BoxFit.contain : BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Center(child: Icon(fallbackIcon, size: 40, color: AppColors.textMuted)),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            f.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          Text(
            _label(f.type),
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
