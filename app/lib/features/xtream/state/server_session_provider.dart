import 'package:flutter/foundation.dart';

import '../../../core/network/api_result.dart';
import '../../auth/data/device_models.dart';
import '../../player/data/play_item.dart';
import '../../progress/data/progress_repository.dart';
import '../data/xtream_client.dart';
import '../data/xtream_models.dart';

enum ConnectionPhase { connecting, ready, failed }

/// Estado do carregamento de uma seção (ao vivo, filmes ou séries).
class SectionState {
  const SectionState({this.loading = false, this.items, this.error});

  final bool loading;
  final List<XtreamCategory>? items;
  final String? error;
}

/// Estado do carregamento dos canais de uma categoria.
class ChannelsState {
  const ChannelsState({this.loading = false, this.items, this.error});

  final bool loading;
  final List<XtreamChannel>? items;
  final String? error;
}

/// Estado genérico de um carregamento (lista de filmes, detalhe de série...).
class LoadState<T> {
  const LoadState({this.loading = false, this.data, this.error});

  final bool loading;
  final T? data;
  final String? error;
}

/// Item da fileira "Continuar assistindo".
class ContinueEntry {
  const ContinueEntry({
    required this.item,
    required this.position,
    required this.duration,
  });

  /// Já com `startAt` na posição salva.
  final PlayItem item;
  final Duration position;
  final Duration duration;

  double get fraction =>
      duration.inSeconds <= 0 ? 0 : (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0);
}

/// Conexão com um servidor Xtream: autentica, carrega categorias e catálogo sob
/// demanda e guarda o progresso de reprodução.
class ServerSessionProvider extends ChangeNotifier {
  ServerSessionProvider(
    this._api,
    this.server, {
    ProgressApi progress = const NullProgressApi(),
  }) : _progress = progress;

  final XtreamApi _api;
  final ProgressApi _progress;
  final XtreamServer server;

  ConnectionPhase _phase = ConnectionPhase.connecting;
  XtreamSession? _session;
  String? _error;
  final Map<XtreamSection, SectionState> _sections = {};
  final Map<String, ChannelsState> _channels = {};
  final Map<String, LoadState<List<XtreamMovie>>> _movies = {};
  final Map<String, LoadState<List<XtreamSeries>>> _series = {};
  final Map<String, LoadState<XtreamSeriesDetail>> _seriesDetail = {};

  // Progresso: mais recente primeiro (ordem de inserção do mapa).
  final Map<String, ProgressEntry> _entries = {};
  final Map<String, PlayItem> _meta = {};
  bool _progressLoaded = false;
  Future<void>? _continueRun;
  List<ContinueEntry> _continue = const [];
  bool _disposed = false;

  ConnectionPhase get phase => _phase;
  XtreamSession? get session => _session;
  String? get error => _error;

  SectionState section(XtreamSection s) => _sections[s] ?? const SectionState();

  ChannelsState channels(String categoryId) =>
      _channels[categoryId] ?? const ChannelsState();

  LoadState<List<XtreamMovie>> movies(String categoryId) =>
      _movies[categoryId] ?? const LoadState();

  LoadState<List<XtreamSeries>> seriesOf(String categoryId) =>
      _series[categoryId] ?? const LoadState();

  LoadState<XtreamSeriesDetail> seriesDetail(String seriesId) =>
      _seriesDetail[seriesId] ?? const LoadState();

  List<ContinueEntry> get continueWatching => _continue;
  bool get continueLoading => _continueRun != null;

  Future<void> connect() async {
    _phase = ConnectionPhase.connecting;
    _error = null;
    _session = null;
    _sections.clear();
    _channels.clear();
    _movies.clear();
    _series.clear();
    _seriesDetail.clear();
    _notify();

    final result = await _api.connect(server);
    if (_disposed) return;

    switch (result) {
      case ApiSuccess<XtreamSession>(:final data):
        _session = data;
        _phase = ConnectionPhase.ready;
      default:
        _error = result.failureMessage;
        _phase = ConnectionPhase.failed;
    }
    _notify();

    if (_phase == ConnectionPhase.ready) {
      loadContinue();
      await loadCategories(XtreamSection.live);
    }
  }

  /// Carrega as categorias da seção, uma única vez (use [force] para recarregar).
  Future<void> loadCategories(XtreamSection section, {bool force = false}) async {
    final session = _session;
    if (session == null) return;

    final current = _sections[section];
    if (!force && current != null && (current.loading || current.items != null)) {
      return;
    }

    _sections[section] = const SectionState(loading: true);
    _notify();

    final result = await _api.categories(session, section);
    if (_disposed) return;

    _sections[section] = switch (result) {
      ApiSuccess<List<XtreamCategory>>(:final data) => SectionState(items: data),
      _ => SectionState(error: result.failureMessage),
    };
    _notify();
  }

  /// Carrega os canais ao vivo de uma categoria, uma única vez por categoria.
  Future<void> loadChannels(String categoryId, {bool force = false}) async {
    final session = _session;
    if (session == null) return;

    final current = _channels[categoryId];
    if (!force && current != null && (current.loading || current.items != null)) {
      return;
    }

    _channels[categoryId] = const ChannelsState(loading: true);
    _notify();

    final result = await _api.liveStreams(session, categoryId);
    if (_disposed) return;

    _channels[categoryId] = switch (result) {
      ApiSuccess<List<XtreamChannel>>(:final data) => ChannelsState(items: data),
      _ => ChannelsState(error: result.failureMessage),
    };
    _notify();
  }

  Future<void> loadMovies(String categoryId, {bool force = false}) => _load(
        _movies,
        categoryId,
        (s) => _api.vodStreams(s, categoryId),
        force: force,
      );

  Future<void> loadSeries(String categoryId, {bool force = false}) => _load(
        _series,
        categoryId,
        (s) => _api.seriesList(s, categoryId),
        force: force,
      );

  Future<void> loadSeriesDetail(String seriesId, {bool force = false}) => _load(
        _seriesDetail,
        seriesId,
        (s) => _api.seriesInfo(s, seriesId),
        force: force,
      );

  Future<void> _load<T>(
    Map<String, LoadState<T>> cache,
    String key,
    Future<ApiResult<T>> Function(XtreamSession) fetch, {
    bool force = false,
  }) async {
    final session = _session;
    if (session == null) return;

    final current = cache[key];
    if (!force && current != null && (current.loading || current.data != null)) {
      return;
    }

    cache[key] = LoadState<T>(loading: true);
    _notify();

    final result = await fetch(session);
    if (_disposed) return;

    cache[key] = switch (result) {
      ApiSuccess<T>(:final data) => LoadState<T>(data: data),
      _ => LoadState<T>(error: result.failureMessage),
    };
    _notify();
  }

  // ---- Itens reproduzíveis -------------------------------------------------

  PlayItem channelItem(XtreamChannel c) => PlayItem(
        title: c.name,
        url: _session!.liveUrl(c),
        kind: PlayKind.live,
        imageUrl: c.iconUrl,
      );

  PlayItem movieItem(XtreamMovie m) => PlayItem(
        title: m.name,
        url: _session!.movieUrl(m.id, m.extension),
        kind: PlayKind.vod,
        progressId: m.id,
        imageUrl: m.posterUrl,
        startAt: _startFor('vod', m.id),
      );

  PlayItem episodeItem(String seriesId, XtreamSeriesDetail d, XtreamEpisode e) =>
      PlayItem(
        title: '${d.name} · T${e.season}:E${e.number} ${e.title}',
        url: _session!.episodeUrl(e.id, e.extension),
        kind: PlayKind.episode,
        progressId: '$seriesId:${e.id}',
        imageUrl: e.thumbUrl ?? d.coverUrl,
        startAt: _startFor('episode', '$seriesId:${e.id}'),
      );

  /// Último episódio da série que ficou pela metade (para o botão "Continuar").
  XtreamEpisode? resumeEpisode(String seriesId, XtreamSeriesDetail d) {
    for (final entry in _entries.values) {
      if (entry.type == 'episode' && entry.id.startsWith('$seriesId:') && _isPartial(entry)) {
        final ep = d.episodeById(entry.id.substring(seriesId.length + 1));
        if (ep != null) return ep;
      }
    }
    return null;
  }

  Duration _startFor(String type, String id) {
    final e = _entries['$type:$id'];
    if (e == null || !_isPartial(e)) return Duration.zero;
    return Duration(seconds: e.positionS);
  }

  static bool _isPartial(ProgressEntry e) =>
      e.durationS > 0 && e.positionS >= 10 && e.positionS / e.durationS < 0.95;

  // ---- Progresso -------------------------------------------------------------

  /// Lê o progresso salvo e descobre título/imagem dos itens (uma vez).
  /// Chamadas simultâneas esperam a mesma execução.
  Future<void> loadContinue({bool force = false}) {
    if (_session == null) return Future<void>.value();
    final running = _continueRun;
    if (running != null) return running;
    if (_progressLoaded && !force) return Future<void>.value();
    final run = _runContinue();
    _continueRun = run;
    return run.whenComplete(() => _continueRun = null);
  }

  Future<void> _runContinue() async {
    final session = _session!;
    _notify();

    final result = await _progress.load(server.id);
    if (_disposed) return;

    if (result is ApiSuccess<List<ProgressEntry>>) {
      _entries.clear();
      for (final e in result.data) {
        _entries[e.key] = e;
      }
      _progressLoaded = true;
    }

    // Só resolve título dos itens que a fileira vai mostrar.
    var resolved = 0;
    for (final e in _entries.values.toList()) {
      if (resolved >= 8) break;
      if (!_isPartial(e)) continue;
      resolved++;
      if (_meta.containsKey(e.key)) continue;
      await _resolveMeta(session, e);
      if (_disposed) return;
    }

    _rebuildContinue();
    _notify();
  }

  Future<void> _resolveMeta(XtreamSession session, ProgressEntry e) async {
    if (e.type == 'vod') {
      final r = await _api.vodInfo(session, e.id);
      if (r is ApiSuccess<XtreamVodInfo>) {
        final info = r.data;
        _meta[e.key] = PlayItem(
          title: info.name,
          url: session.movieUrl(e.id, info.extension),
          kind: PlayKind.vod,
          progressId: e.id,
          imageUrl: info.imageUrl,
        );
      }
    } else if (e.type == 'episode') {
      final sep = e.id.indexOf(':');
      if (sep <= 0) return;
      final seriesId = e.id.substring(0, sep);
      await loadSeriesDetail(seriesId);
      final detail = _seriesDetail[seriesId]?.data;
      final ep = detail?.episodeById(e.id.substring(sep + 1));
      if (detail != null && ep != null) {
        _meta[e.key] = episodeItem(seriesId, detail, ep).withStart(Duration.zero);
      }
    }
  }

  void _rebuildContinue() {
    _continue = [
      for (final e in _entries.values)
        if (_isPartial(e) && _meta.containsKey(e.key))
          ContinueEntry(
            item: _meta[e.key]!.withStart(Duration(seconds: e.positionS)),
            position: Duration(seconds: e.positionS),
            duration: Duration(seconds: e.durationS),
          ),
    ].take(10).toList();
  }

  /// Chamado pelo player (a cada ~30 s e ao sair). Atualiza a lista na hora e
  /// salva no backend sem esperar a resposta.
  void recordProgress(PlayItem item, Duration position, Duration duration) {
    final id = item.progressId;
    if (item.isLive || id == null || duration.inSeconds <= 0 || position.inSeconds < 5) {
      return;
    }
    final entry = ProgressEntry(
      type: item.kind == PlayKind.vod ? 'vod' : 'episode',
      id: id,
      positionS: position.inSeconds,
      durationS: duration.inSeconds,
    );
    _entries.remove(entry.key);
    final reordered = {entry.key: entry, ..._entries};
    _entries
      ..clear()
      ..addAll(reordered);
    _meta[entry.key] = item.withStart(Duration.zero);
    _rebuildContinue();
    _progress.save(server.id, entry);
    // O player chama isto ao fechar; notificar depois do quadro atual.
    Future<void>.microtask(_notify);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
