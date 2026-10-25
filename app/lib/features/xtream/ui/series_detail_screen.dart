import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/focus_ring.dart';
import '../../../core/ui/focus_tile.dart';
import '../../favorites/data/favorites_repository.dart';
import '../../favorites/ui/favorite_actions.dart';
import '../../player/ui/play_launcher.dart';
import '../data/xtream_models.dart';
import '../state/server_session_provider.dart';

/// Detalhe de uma série: sinopse, temporadas e episódios.
class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({super.key, required this.series});

  final XtreamSeries series;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  int? _season;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ServerSessionProvider>().loadSeriesDetail(widget.series.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerSessionProvider>();
    final state = provider.seriesDetail(widget.series.id);
    final detail = state.data;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Voltar',
                    icon: const Icon(Icons.arrow_back),
                    style: ButtonStyle(
                      side: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.focused)
                            ? const BorderSide(color: Colors.white, width: 2)
                            : null,
                      ),
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.series.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Builder(builder: (context) {
                    final entry = FavoriteEntry(
                      type: FavoriteType.series,
                      id: widget.series.id,
                      name: widget.series.name,
                      imageUrl: widget.series.coverUrl,
                    );
                    final on = provider.isFavorite(entry.type, entry.id);
                    return IconButton(
                      tooltip: on ? 'Remover da Minha lista' : 'Adicionar à Minha lista',
                      icon: Icon(on ? Icons.favorite : Icons.favorite_border,
                          color: on ? AppColors.accent : null),
                      style: ButtonStyle(
                        side: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.focused)
                              ? const BorderSide(color: Colors.white, width: 2)
                              : null,
                        ),
                      ),
                      onPressed: () => toggleFavoriteWithMessage(context, entry),
                    );
                  }),
                ],
              ),
              Expanded(child: _body(provider, state, detail)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(
    ServerSessionProvider provider,
    LoadState<XtreamSeriesDetail> state,
    XtreamSeriesDetail? detail,
  ) {
    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              style: focusRingStyle(),
              autofocus: true,
              onPressed: () =>
                  provider.loadSeriesDetail(widget.series.id, force: true),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }
    if (detail == null) return const Center(child: CircularProgressIndicator());
    if (detail.seasons.isEmpty) {
      return const Center(child: Text('Esta série ainda não tem episódios.'));
    }

    final seasons = detail.seasons.keys.toList();
    final season = detail.seasons.containsKey(_season) ? _season! : seasons.first;
    final episodes = detail.seasons[season]!;
    final resume = provider.resumeEpisode(widget.series.id, detail);
    final plot = detail.plot ?? widget.series.plot;
    final meta = [
      if ((detail.year ?? widget.series.year) != null) detail.year ?? widget.series.year!,
      if ((detail.rating ?? widget.series.rating) != null)
        '★ ${detail.rating ?? widget.series.rating}',
      '${seasons.length} temporada${seasons.length == 1 ? '' : 's'}',
    ].join('  ·  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 0, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(meta, style: const TextStyle(color: AppColors.textMuted, fontSize: 16)),
              if (plot != null) ...[
                const SizedBox(height: 8),
                Text(plot,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, height: 1.4)),
              ],
              if (resume != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  autofocus: true,
                  style: focusRingStyle(),
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Continuar T${resume.season}:E${resume.number}'),
                  onPressed: () {
                    final q = provider.episodeQueue(widget.series.id, detail, resume);
                    launchPlayer(context, q.items, index: q.index);
                  },
                ),
              ],
            ],
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final s in seasons)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ChoiceChip(
                    label: Text('Temporada $s'),
                    selected: s == season,
                    onSelected: (_) => setState(() => _season = s),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: episodes.length,
            itemBuilder: (context, i) {
              final e = episodes[i];
              return FocusTile(
                autofocus: resume == null && i == 0,
                onTap: () {
                  final q = provider.episodeQueue(widget.series.id, detail, e);
                  launchPlayer(context, q.items, index: q.index);
                },
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text('E${e.number}',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: Text(e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                    if (e.duration != null)
                      Text(formatDuration(e.duration!),
                          style: const TextStyle(color: AppColors.textMuted)),
                    const SizedBox(width: 12),
                    const Icon(Icons.play_arrow),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
