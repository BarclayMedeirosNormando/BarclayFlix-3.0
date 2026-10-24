import 'package:flutter/foundation.dart';

import '../../../core/network/api_result.dart';
import '../../auth/data/device_models.dart';
import '../data/xtream_client.dart';
import '../data/xtream_models.dart';

enum ConnectionPhase { connecting, ready, failed }

/// Estado de carregamento de uma seção (ao vivo, filmes ou séries).
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

/// Conexão com um servidor Xtream: autentica e carrega as categorias sob demanda.
class ServerSessionProvider extends ChangeNotifier {
  ServerSessionProvider(this._api, this.server);

  final XtreamApi _api;
  final XtreamServer server;

  ConnectionPhase _phase = ConnectionPhase.connecting;
  XtreamSession? _session;
  String? _error;
  final Map<XtreamSection, SectionState> _sections = {};
  final Map<String, ChannelsState> _channels = {};
  bool _disposed = false;

  ConnectionPhase get phase => _phase;
  XtreamSession? get session => _session;
  String? get error => _error;

  SectionState section(XtreamSection s) => _sections[s] ?? const SectionState();

  Future<void> connect() async {
    _phase = ConnectionPhase.connecting;
    _error = null;
    _session = null;
    _sections.clear();
    _channels.clear();
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

  ChannelsState channels(String categoryId) =>
      _channels[categoryId] ?? const ChannelsState();

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

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
