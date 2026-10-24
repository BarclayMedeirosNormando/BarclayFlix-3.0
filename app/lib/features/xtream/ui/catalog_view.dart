import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/focus_ring.dart';
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
  late XtreamCategory _category = widget.categories.first;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 64,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            itemCount: widget.categories.length,
            itemBuilder: (context, i) {
              final c = widget.categories[i];
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
        for (final m in state.data ?? const <XtreamMovie>[])
          _PosterData(
            title: m.name,
            subtitle: m.rating == null ? null : '★ ${m.rating}',
            imageUrl: m.posterUrl,
            onTap: () => launchPlayer(context, [provider.movieItem(m)]),
          ),
      ];
    } else {
      final state = provider.seriesOf(_category.id);
      error = state.error;
      loaded = state.data != null;
      posters = [
        for (final s in state.data ?? const <XtreamSeries>[])
          _PosterData(
            title: s.name,
            subtitle: [if (s.year != null) s.year!, if (s.rating != null) '★ ${s.rating}']
                .join('  ·  '),
            imageUrl: s.coverUrl,
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

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisExtent: 320,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
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
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final VoidCallback onTap;
}

class _Chip extends StatefulWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

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
              child: d.imageUrl == null
                  ? const _PosterFallback()
                  : Image.network(
                      d.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _PosterFallback(),
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
