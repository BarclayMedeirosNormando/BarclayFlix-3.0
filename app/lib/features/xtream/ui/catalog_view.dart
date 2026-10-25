import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/device/device_profile.dart';
import '../../../core/text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/focus_ring.dart';
import '../../favorites/data/favorites_repository.dart';
import '../../favorites/ui/favorite_actions.dart';
import '../../player/ui/play_launcher.dart';
import '../data/xtream_models.dart';
import '../state/server_session_provider.dart';
import 'series_detail_screen.dart';

/// Grade de pôsteres de Filmes ou Séries, com as categorias em faixa no topo.
class CatalogView extends StatefulWidget {
  const CatalogView({super.key, required this.section, required this.categories})
      : assert(section == XtreamSection.vod || section == XtreamSection.series);

  final XtreamSection section;
  final List<XtreamCategory> categories;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  /// "Todos" primeiro (id vazio = sem filtro de categoria na API), depois as categorias.
  late final List<XtreamCategory> _cats = [
    const XtreamCategory(id: '', name: 'Todos'),
    ...widget.categories,
  ];

  late XtreamCategory _category = _cats.first;

  /// false = mais recentes primeiro (ordem da API); true = A–Z.
  bool _alpha = false;
  Object? _sortedSrc;
  List<Object?> _sorted = const [];

  List<T> _order<T>(List<T>? src, String Function(T) name) {
    if (src == null) return const [];
    if (!_alpha) return src;
    if (!identical(src, _sortedSrc)) {
      _sortedSrc = src;
      _sorted = [...src]..sort((a, b) =>
          normalizeForSearch(name(a as T)).compareTo(normalizeForSearch(name(b as T))));
    }
    return _sorted.cast<T>();
  }

  bool get _isMovies => widget.section == XtreamSection.vod;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCurrent());
  }

  void _loadCurrent({bool force = false}) {
    if (!mounted) return;
    final p = context.read<ServerSessionProvider>();
    if (_isMovies) {
      p.loadMovies(_category.id, force: force);
    } else {
      p.loadSeries(_category.id, force: force);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerSessionProvider>();
    final compact = DeviceProfile.of(context).compact;
    final edge = compact ? 14.0 : 24.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: compact ? 56 : 64,
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.fromLTRB(edge, 8, 12, 8),
                  itemCount: _cats.length,
                  itemBuilder: (context, i) {
                    final c = _cats[i];
                    return _Chip(
                      label: c.name,
                      selected: c.id == _category.id,
                      onTap: () {
                        setState(() => _category = c);
                        _loadCurrent();
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
                child: _Chip(
                  label: 'Recentes',
                  icon: Icons.schedule,
                  selected: !_alpha,
                  onTap: () => setState(() => _alpha = false),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(0, 8, edge, 8),
                child: _Chip(
                  label: 'A–Z',
                  icon: Icons.sort_by_alpha,
                  selected: _alpha,
                  onTap: () => setState(() => _alpha = true),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _grid(provider)),
      ],
    );
  }

  Widget _grid(ServerSessionProvider provider) {
    final String? error;
    final bool loaded;
    final List<_PosterData> posters;

    if (_isMovies) {
      final state = provider.movies(_category.id);
      error = state.error;
      loaded = state.data != null;
      posters = [
        for (final m in _order<XtreamMovie>(state.data, (m) => m.name))
          _PosterData(
            title: m.name,
            subtitle: m.rating == null ? null : '★ ${m.rating}',
            imageUrl: m.posterUrl,
            favorite: FavoriteEntry(
              type: FavoriteType.vod,
              id: m.id,
              name: m.name,
              imageUrl: m.posterUrl,
            ),
            onTap: () => launchPlayer(context, [provider.movieItem(m)]),
          ),
      ];
    } else {
      final state = provider.seriesOf(_category.id);
      error = state.error;
      loaded = state.data != null;
      posters = [
        for (final s in _order<XtreamSeries>(state.data, (s) => s.name))
          _PosterData(
            title: s.name,
            subtitle: [if (s.year != null) s.year!, if (s.rating != null) '★ ${s.rating}']
                .join('  ·  '),
            imageUrl: s.coverUrl,
            favorite: FavoriteEntry(
              type: FavoriteType.series,
              id: s.id,
              name: s.name,
              imageUrl: s.coverUrl,
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ChangeNotifierProvider<ServerSessionProvider>.value(
                value: provider,
                child: SeriesDetailScreen(series: s),
              ),
            )),
          ),
      ];
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              style: focusRingStyle(),
              onPressed: () => _loadCurrent(force: true),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }
    if (!loaded) return const Center(child: CircularProgressIndicator());
    if (posters.isEmpty) return const Center(child: Text('Nada nesta categoria.'));

    final profile = DeviceProfile.of(context);
    // Tamanho dos pôsteres por tipo de aparelho (celular: 3 colunas; TV/PC: maiores).
    final (double maxW, double h, double gap, double edge) = switch (profile.kind) {
      DeviceClass.phone => (150.0, 268.0, 12.0, 14.0),
      DeviceClass.tablet => (180.0, 300.0, 16.0, 20.0),
      _ => (200.0, 320.0, 20.0, 24.0),
    };
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(edge, 8, edge, 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxW,
        mainAxisExtent: h,
        mainAxisSpacing: gap,
        crossAxisSpacing: gap,
      ),
      itemCount: posters.length,
      itemBuilder: (context, i) => _PosterCard(data: posters[i], autofocus: i == 0),
    );
  }
}

class _PosterData {
  const _PosterData({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.imageUrl,
    this.favorite,
  });

  final FavoriteEntry? favorite;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final VoidCallback onTap;
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon,
                    size: 18, color: widget.selected ? AppColors.onAccent : Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: widget.selected ? AppColors.onAccent : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cartão de pôster (filme ou série) com anel de foco.
class _PosterCard extends StatefulWidget {
  const _PosterCard({required this.data, this.autofocus = false});

  final _PosterData data;
  final bool autofocus;

  @override
  State<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<_PosterCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return InkWell(
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(14),
      onTap: d.onTap,
      onLongPress: d.favorite == null
          ? null
          : () => toggleFavoriteWithMessage(context, d.favorite!),
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) ensureVisibleOnFocus(context);
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  d.imageUrl == null
                      ? const _PosterFallback()
                      : Image.network(
                          d.imageUrl!,
                          fit: BoxFit.cover,
                          cacheWidth: 360,
                          filterQuality: FilterQuality.low,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => const _PosterFallback(),
                        ),
                  if (d.favorite != null &&
                      context
                          .watch<ServerSessionProvider>()
                          .isFavorite(d.favorite!.type, d.favorite!.id))
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(Icons.favorite, color: AppColors.accent, size: 22),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            d.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if (d.subtitle != null && d.subtitle!.isNotEmpty)
            Text(
              d.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) =>
      const Center(child: Icon(Icons.movie_outlined, size: 40, color: AppColors.textMuted));
}
