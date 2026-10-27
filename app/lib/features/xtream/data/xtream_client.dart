import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../core/cache/list_cache.dart';
import '../../../core/network/api_result.dart';
import '../../auth/data/device_models.dart';
import 'xtream_models.dart';

/// Contrato mínimo usado pelo estado do app (facilita testes).
abstract interface class XtreamApi {
  Future<ApiResult<XtreamSession>> connect(XtreamServer server);

  Future<ApiResult<List<XtreamCategory>>> categories(
    XtreamSession session,
    XtreamSection section,
  );

  Future<ApiResult<List<XtreamChannel>>> liveStreams(
    XtreamSession session,
    String categoryId,
  );

  Future<ApiResult<List<XtreamMovie>>> vodStreams(
    XtreamSession session,
    String categoryId,
  );

  Future<ApiResult<List<XtreamSeries>>> seriesList(
    XtreamSession session,
    String categoryId,
  );

  Future<ApiResult<XtreamSeriesDetail>> seriesInfo(
    XtreamSession session,
    String seriesId,
  );

  Future<ApiResult<XtreamVodInfo>> vodInfo(
    XtreamSession session,
    String vodId,
  );

  /// Programa atual e próximos de um canal (lista vazia se o painel não tiver guia).
  Future<ApiResult<List<EpgEntry>>> shortEpg(
    XtreamSession session,
    String streamId,
  );
}

/// Leitura das listas guardadas no aparelho (para mostrar na hora ao abrir).
/// Opcional: quem não implementa simplesmente não tem cache.
abstract interface class XtreamCachedLists {
  Future<List<XtreamCategory>?> cachedCategories(XtreamSession s, XtreamSection section);
  Future<List<XtreamChannel>?> cachedChannels(XtreamSession s, String categoryId);
  Future<List<XtreamMovie>?> cachedMovies(XtreamSession s, String categoryId);
  Future<List<XtreamSeries>?> cachedSeries(XtreamSession s, String categoryId);
}

/// Cliente da API Xtream Codes (`player_api.php`).
///
/// - Testa os hosts do servidor em ordem e usa o primeiro que responder.
/// - Normaliza o host (sem barra final, `http://` se faltar o esquema).
/// - Nunca lança exceção e nunca guarda a URL (que leva usuário e senha)
///   em mensagens de erro.
class XtreamClient implements XtreamApi, XtreamCachedLists {
  XtreamClient({
    http.Client? httpClient,
    this.authTimeout = const Duration(seconds: 12),
    this.listTimeout = const Duration(seconds: 30),
    ListCache? cache,
  })  : _http = httpClient ?? _lenientClient(),
        _cache = cache;

  final ListCache? _cache;

  /// Painéis de IPTV costumam ter certificado HTTPS vencido, autoassinado ou de outro
  /// domínio (e redirecionam o http para ele). O navegador deixa passar; o Dart recusa
  /// com `HandshakeException`. Este cliente só fala com os servidores do próprio
  /// usuário, que já usam http puro, então aceitar o certificado não expõe mais nada.
  static http.Client _lenientClient() {
    final inner = HttpClient();
    inner.connectionTimeout = const Duration(seconds: 15);
    inner.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return IOClient(inner);
  }

  final Duration authTimeout;
  final Duration listTimeout;
  final http.Client _http;

  void dispose() => _http.close();

  /// `http://granfox.xyz/` → `http://granfox.xyz`; `dns.xyz:8080` → `http://dns.xyz:8080`.
  static Uri? baseUri(String host) {
    var h = host.trim();
    if (h.isEmpty) return null;
    if (!h.contains('://')) h = 'http://$h';
    h = h.replaceAll(RegExp(r'/+$'), '');
    // Quem cadastra costuma colar o link inteiro (`.../player_api.php?...` ou `.../get.php`):
    // fica só o endereço base, porque o app acrescenta o caminho da API.
    h = h
        .replaceFirst(
          RegExp(r'/(player_api|get|panel_api|xmltv)\.php(\?.*)?$', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(h);
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  @override
  Future<ApiResult<XtreamSession>> connect(XtreamServer server) async {
    ApiResult<XtreamSession>? last;
    for (final host in server.hosts) {
      final base = baseUri(host);
      if (base == null) {
        last = const ApiBadPayload<XtreamSession>('Endereço de servidor inválido.');
        continue;
      }
      for (final candidate in _variants(base)) {
        final result = await _authenticate(server, candidate);
        if (result is ApiSuccess<XtreamSession>) return result;
        // Credenciais recusadas: outro DNS do mesmo painel não vai mudar isso.
        if (result is ApiError<XtreamSession>) return result;
        last = result;
      }
    }
    return last ?? const ApiBadPayload<XtreamSession>('Servidor sem endereço.');
  }

  /// O endereço como foi cadastrado e, se falhar, o mesmo com http↔https: há painéis
  /// que só atendem em um dos dois, e o DNS informado ao cliente nem sempre é o certo.
  /// Só vale sem porta explícita (com porta, o esquema não se adivinha).
  static List<Uri> _variants(Uri base) {
    if (base.hasPort || (base.scheme != 'http' && base.scheme != 'https')) return [base];
    final other = base.scheme == 'https' ? 'http' : 'https';
    return [base, base.replace(scheme: other)];
  }

  @override
  Future<ApiResult<List<XtreamCategory>>> categories(
    XtreamSession session,
    XtreamSection section,
  ) =>
      _listOf(session, section.action, const {}, XtreamCategory.fromJson, 'categorias');

  @override
  Future<ApiResult<List<XtreamChannel>>> liveStreams(
    XtreamSession session,
    String categoryId,
  ) =>
      _listOf(
        session,
        'get_live_streams',
        // Vazio = todos os canais (usado pela busca).
        {if (categoryId.isNotEmpty) 'category_id': categoryId},
        XtreamChannel.fromJson,
        'canais',
      );

  @override
  Future<ApiResult<List<XtreamMovie>>> vodStreams(
    XtreamSession session,
    String categoryId,
  ) =>
      _newestFirst(
        _listOf(session, 'get_vod_streams', {if (categoryId.isNotEmpty) 'category_id': categoryId},
            XtreamMovie.fromJson, 'filmes'),
        (m) => m.added,
      );

  @override
  Future<ApiResult<List<XtreamSeries>>> seriesList(
    XtreamSession session,
    String categoryId,
  ) =>
      _newestFirst(
        _listOf(session, 'get_series', {if (categoryId.isNotEmpty) 'category_id': categoryId},
            XtreamSeries.fromJson, 'séries'),
        (s) => s.added,
      );

  /// Mais recentes primeiro (data de entrada no servidor); sem data, mantém a ordem original.
  Future<ApiResult<List<T>>> _newestFirst<T>(
    Future<ApiResult<List<T>>> future,
    int Function(T) added,
  ) async {
    final r = await future;
    if (r is! ApiSuccess<List<T>>) return r;
    final list = r.data;
    if (list.every((e) => added(e) == 0)) return r;
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((a, b) {
      final c = added(b.$2).compareTo(added(a.$2));
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return ApiSuccess<List<T>>([for (final e in indexed) e.$2]);
  }

  @override
  Future<ApiResult<XtreamSeriesDetail>> seriesInfo(
    XtreamSession session,
    String seriesId,
  ) async {
    final uri = _playerApi(session.baseUri, session.server,
        {'action': 'get_series_info', 'series_id': seriesId});
    final result = await _getJson(uri, listTimeout);
    if (result is! ApiSuccess<Object?>) return _fail<XtreamSeriesDetail>(result);
    final data = result.data;
    if (data is! Map<String, dynamic>) {
      return ApiBadPayload<XtreamSeriesDetail>('Detalhe da série inesperado.');
    }
    try {
      return ApiSuccess<XtreamSeriesDetail>(XtreamSeriesDetail.fromJson(data));
    } on TypeError {
      return ApiBadPayload<XtreamSeriesDetail>('Série com formato inesperado.');
    }
  }

  @override
  Future<ApiResult<XtreamVodInfo>> vodInfo(
    XtreamSession session,
    String vodId,
  ) async {
    final uri = _playerApi(session.baseUri, session.server,
        {'action': 'get_vod_info', 'vod_id': vodId});
    final result = await _getJson(uri, listTimeout);
    if (result is! ApiSuccess<Object?>) return _fail<XtreamVodInfo>(result);
    final data = result.data;
    if (data is! Map<String, dynamic>) {
      return ApiBadPayload<XtreamVodInfo>('Detalhe do filme inesperado.');
    }
    try {
      return ApiSuccess<XtreamVodInfo>(XtreamVodInfo.fromJson(data, vodId));
    } on TypeError {
      return ApiBadPayload<XtreamVodInfo>('Filme com formato inesperado.');
    }
  }

  @override
  Future<ApiResult<List<EpgEntry>>> shortEpg(
    XtreamSession session,
    String streamId,
  ) async {
    final uri = _playerApi(session.baseUri, session.server,
        {'action': 'get_short_epg', 'stream_id': streamId, 'limit': '4'});
    final result = await _getJson(uri, authTimeout);
    if (result is! ApiSuccess<Object?>) return _fail<List<EpgEntry>>(result);
    final data = result.data;
    final list = data is Map<String, dynamic> ? data['epg_listings'] : null;
    if (list is! List<dynamic>) return const ApiSuccess<List<EpgEntry>>([]);
    final entries = <EpgEntry>[
      for (final e in list)
        if (e is Map<String, dynamic>)
          if (EpgEntry.fromJson(e) case final x?) x,
    ]..sort((a, b) => a.start.compareTo(b.start));
    return ApiSuccess<List<EpgEntry>>(entries);
  }

  Future<ApiResult<List<T>>> _listOf<T>(
    XtreamSession session,
    String action,
    Map<String, String> extra,
    T Function(JsonMap) parse,
    String label,
  ) async {
    final uri = _playerApi(session.baseUri, session.server, {'action': action, ...extra});
    final result = await _getJson(uri, listTimeout);
    if (result is! ApiSuccess<Object?>) return _fail<List<T>>(result);
    final data = result.data;
    if (data is! List<dynamic>) {
      return ApiBadPayload<List<T>>('Lista de $label inesperada.');
    }
    try {
      final list = data.length > _bigList
          ? await _mapInBackground(data, parse)
          : [for (final e in data) parse(e as Map<String, dynamic>)];
      _remember(_cacheKey(session, action, extra), data);
      return ApiSuccess<List<T>>(list);
    } on TypeError {
      return ApiBadPayload<List<T>>('Item de $label com formato inesperado.');
    } on RemoteError {
      // Mesmo erro, mas ocorrido no processamento em segundo plano.
      return ApiBadPayload<List<T>>('Item de $label com formato inesperado.');
    }
  }

  // ---- Cache em disco ------------------------------------------------------

  /// Listas acima disso são lidas/gravadas em segundo plano (não travam a tela).
  static const _bigList = 400;

  String _cacheKey(XtreamSession s, String action, Map<String, String> extra) =>
      '${s.server.id}_${action}_${extra['category_id'] ?? 'all'}';

  /// Grava a lista no disco sem atrasar quem chamou.
  void _remember(String key, List<dynamic> data) {
    final cache = _cache;
    if (cache == null) return;
    final text = data.length > _bigList
        ? _encodeInBackground(data)
        : Future<String>.value(jsonEncode(data));
    text.then((t) => cache.write(key, t)).catchError((Object _) {});
  }

  Future<List<T>?> _readCached<T>(
    XtreamSession session,
    String action,
    Map<String, String> extra,
    T Function(JsonMap) parse,
  ) async {
    final cache = _cache;
    if (cache == null) return null;
    try {
      final text = await cache.read(_cacheKey(session, action, extra));
      if (text == null) return null;
      return text.length > 150000
          ? await _decodeListInBackground(text, parse)
          : _decodeList(text, parse);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<XtreamCategory>?> cachedCategories(XtreamSession s, XtreamSection section) =>
      _readCached(s, section.action, const {}, XtreamCategory.fromJson);

  @override
  Future<List<XtreamChannel>?> cachedChannels(XtreamSession s, String categoryId) => _readCached(
      s, 'get_live_streams', {if (categoryId.isNotEmpty) 'category_id': categoryId}, XtreamChannel.fromJson);

  @override
  Future<List<XtreamMovie>?> cachedMovies(XtreamSession s, String categoryId) async {
    final l = await _readCached(
        s, 'get_vod_streams', {if (categoryId.isNotEmpty) 'category_id': categoryId}, XtreamMovie.fromJson);
    return l == null ? null : _sortNewest(l, (m) => m.added);
  }

  @override
  Future<List<XtreamSeries>?> cachedSeries(XtreamSession s, String categoryId) async {
    final l = await _readCached(
        s, 'get_series', {if (categoryId.isNotEmpty) 'category_id': categoryId}, XtreamSeries.fromJson);
    return l == null ? null : _sortNewest(l, (m) => m.added);
  }

  // Auxiliares ESTÁTICOS e sem async: o closure enviado ao isolate só captura os
  // argumentos (capturar `this` levaria o http.Client, que não pode ser enviado).
  static Future<List<T>> _mapInBackground<T>(List<dynamic> data, T Function(JsonMap) parse) =>
      Isolate.run(() => [for (final e in data) parse(e as Map<String, dynamic>)]);

  static Future<String> _encodeInBackground(List<dynamic> data) =>
      Isolate.run(() => jsonEncode(data));

  static Future<Object?> _jsonInBackground(String body) => Isolate.run(() => jsonDecode(body));

  static List<T> _decodeList<T>(String text, T Function(JsonMap) parse) => [
        for (final e in jsonDecode(text) as List<dynamic>) parse(e as Map<String, dynamic>),
      ];

  static Future<List<T>> _decodeListInBackground<T>(String text, T Function(JsonMap) parse) =>
      Isolate.run(() => _decodeList(text, parse));

  static List<T> _sortNewest<T>(List<T> list, int Function(T) added) {
    if (list.every((e) => added(e) == 0)) return list;
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((a, b) {
      final c = added(b.$2).compareTo(added(a.$2));
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  Future<ApiResult<XtreamSession>> _authenticate(XtreamServer server, Uri base) async {
    final result = await _getJson(_playerApi(base, server, const {}), authTimeout);
    if (result is! ApiSuccess<Object?>) return _fail<XtreamSession>(result);

    final data = result.data;
    if (data is! Map<String, dynamic>) {
      return const ApiBadPayload<XtreamSession>('Resposta de autenticação inesperada.');
    }
    final userInfo = data['user_info'];
    if (userInfo is! Map<String, dynamic>) {
      return const ApiBadPayload<XtreamSession>('Resposta sem dados da conta.');
    }
    final info = XtreamUserInfo.fromJson(userInfo);
    if (!info.authorized) {
      return const ApiError<XtreamSession>(
        'AUTH_FAILED',
        'Usuário ou senha recusados pelo servidor.',
      );
    }
    return ApiSuccess<XtreamSession>(
      XtreamSession(server: server, baseUri: base, userInfo: info),
    );
  }

  Uri _playerApi(Uri base, XtreamServer server, Map<String, String> extra) =>
      base.replace(
        path: '${base.path}/player_api.php',
        queryParameters: {
          'username': server.username,
          'password': server.password,
          ...extra,
        },
      );

  /// Painéis Xtream (XUI) costumam recusar o nome padrão do Dart; players de IPTV
  /// se identificam assim e são aceitos.
  static const Map<String, String> _headers = {
    'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20',
    'Accept': '*/*',
  };

  /// Esquema, host, porta e caminho (sem usuário e senha) para a mensagem de erro.
  static String _where(Uri uri) => '${uri.scheme}://${uri.host}:${uri.port}${uri.path}';

  Future<ApiResult<Object?>> _getJson(Uri uri, Duration timeout) async {
    try {
      final response = await _http.get(uri, headers: _headers).timeout(timeout);
      if (response.statusCode != 200) {
        return ApiNetworkError<Object?>('HTTP ${response.statusCode} · ${_where(uri)}');
      }
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      try {
        final decoded =
            body.length > 150000 ? await _jsonInBackground(body) : jsonDecode(body);
        return ApiSuccess<Object?>(decoded);
      } on FormatException {
        return const ApiBadPayload<Object?>('Resposta não é JSON.');
      } on RemoteError {
        return const ApiBadPayload<Object?>('Resposta não é JSON.');
      }
    } on TimeoutException {
      return ApiTimeout<Object?>();
    } on Exception catch (e) {
      // Só o tipo: a mensagem da exceção pode conter a URL com a senha.
      return ApiNetworkError<Object?>('${e.runtimeType} · ${_where(uri)}');
    }
  }

  ApiResult<T> _fail<T>(ApiResult<Object?> r) => switch (r) {
        ApiSuccess<Object?>() => ApiBadPayload<T>('Resposta inesperada.'),
        ApiError<Object?>(:final code, :final message) => ApiError<T>(code, message),
        ApiNetworkError<Object?>(:final message) => ApiNetworkError<T>(message),
        ApiTimeout<Object?>() => ApiTimeout<T>(),
        ApiBadPayload<Object?>(:final message) => ApiBadPayload<T>(message),
      };
}
