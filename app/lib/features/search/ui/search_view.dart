import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/focus_tile.dart';
import '../../favorites/data/favorites_repository.dart';
import '../../favorites/ui/favorite_actions.dart';
import '../../player/ui/play_launcher.dart';
import '../../xtream/data/xtream_models.dart';
import '../../xtream/state/server_session_provider.dart';
import '../../xtream/ui/live_view.dart' show ChannelLogo;
import '../../xtream/ui/series_detail_screen.dart';

/// Máximo de resultados mostrados por busca.
const int kMaxSearchResults = 60;

/// Aba "Busca": procura canais, filmes e séries do servidor pelo nome.
/// A lista completa do tipo é baixada uma vez e filtrada no aparelho.
class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  FavoriteType _type = FavoriteType.live;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = normalizeForSearch(text));
    });
  }

  void _setType(FavoriteType t) {
    setState(() => _type = t);
    context.read<ServerSessionProvider>().ensureSearchData(t);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ServerSessionProvider>().ensureSearchData(_type);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerSessionProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Digite o nome do canal, filme ou série',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.white, width: 2),
              ),
            ),
            onChanged: (t) {
              setState(() {}); // atualiza o botão de limpar
              _onChanged(t);
            },
            onSubmitted: (t) => setState(() => _query = normalizeForSearch(t)),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            children: [
              for (final t in FavoriteType.values)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ChoiceChip(
                    label: Text(switch (t) {
                      FavoriteType.live => 'Canais',
                      FavoriteType.vod => 'Filmes',
                      FavoriteType.series => 'Séries',
                    }),
                    selected: t == _type,
                    onSelected: (_) => _setType(t),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _results(provider)),
      ],
    );
  }

  Widget _results(ServerSessionProvider provider) {
    final String? error;
    final bool loaded;
    switch (_type) {
      case FavoriteType.live:
        final s = provider.channels('');
        error = s.error;
        loaded = s.items != null;
      case FavoriteType.vod:
        final s = provider.movies('');
        error = s.error;
        loaded = s.data != null;
      case FavoriteType.series:
        final s = provider.seriesOf('');
        error = s.error;
        loaded = s.data != null;
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                switch (_type) {
                  case FavoriteType.live:
                    provider.loadChannels('', force: true);
                  case FavoriteType.vod:
                    provider.loadMovies('', force: true);
                  case FavoriteType.series:
                    provider.loadSeries('', force: true);
                }
              },
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }
    if (!loaded) return const Center(child: CircularProgressIndicator());
    if (_query.length < 2) {
      return const Center(
        child: Text('Digite ao menos 2 letras.', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    final rows = _search(provider);
    if (rows.isEmpty) return const Center(child: Text('Nada encontrado.'));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final r = rows[i];
        return FocusTile(
          onTap: r.onTap,
          onLongPress: () => toggleFavoriteWithMessage(context, r.favorite),
          child: Row(
            children: [
              ChannelLogo(url: r.favorite.imageUrl, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  r.favorite.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              if (provider.isFavorite(r.favorite.type, r.favorite.id))
                const Icon(Icons.favorite, size: 20, color: AppColors.accent),
            ],
          ),
        );
      },
    );
  }

  List<_Row> _search(ServerSessionProvider provider) {
    bool hit(String name) => normalizeForSearch(name).contains(_query);
    final rows = <_Row>[];

    switch (_type) {
      case FavoriteType.live:
        final all = provider.channels('').items ?? const <XtreamChannel>[];
        final found = <XtreamChannel>[];
        for (final c in all) {
          if (!hit(c.name)) continue;
          found.add(c);
          if (found.length >= kMaxSearchResults) break;
        }
        for (final (i, c) in found.indexed) {
          rows.add(_Row(
            FavoriteEntry(type: FavoriteType.live, id: c.id, name: c.name, imageUrl: c.iconUrl),
            () => launchPlayer(
              context,
              [for (final x in found) provider.channelItem(x)],
              index: i,
            ),
          ));
        }
      case FavoriteType.vod:
        final all = provider.movies('').data ?? const <XtreamMovie>[];
        for (final m in all) {
          if (!hit(m.name)) continue;
          rows.add(_Row(
            FavoriteEntry(type: FavoriteType.vod, id: m.id, name: m.name, imageUrl: m.posterUrl),
            () => launchPlayer(context, [provider.movieItem(m)]),
          ));
          if (rows.length >= kMaxSearchResults) break;
        }
      case FavoriteType.series:
        final all = provider.seriesOf('').data ?? const <XtreamSeries>[];
        for (final s in all) {
          if (!hit(s.name)) continue;
          rows.add(_Row(
            FavoriteEntry(type: FavoriteType.series, id: s.id, name: s.name, imageUrl: s.coverUrl),
            () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ChangeNotifierProvider<ServerSessionProvider>.value(
                value: provider,
                child: SeriesDetailScreen(series: s),
              ),
            )),
          ));
          if (rows.length >= kMaxSearchResults) break;
        }
    }
    return rows;
  }
}

class _Row {
  const _Row(this.favorite, this.onTap);

  final FavoriteEntry favorite;
  final VoidCallback onTap;
}
