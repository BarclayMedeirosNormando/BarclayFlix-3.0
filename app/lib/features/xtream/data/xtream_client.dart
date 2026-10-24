import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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
}

/// Cliente da API Xtream Codes (`player_api.php`).
///
/// - Testa os hosts do servidor em ordem e usa o primeiro que responder.
/// - Normaliza o host (sem barra final, `http://` se faltar o esquema).
/// - Nunca lança exceção e nunca guarda a URL (que leva usuário e senha)
///   em mensagens de erro.
class XtreamClient implements XtreamApi {
  XtreamClient({
    http.Client? httpClient,
    this.authTimeout = const Duration(seconds: 12),
    this.listTimeout = const Duration(seconds: 30),
  }) : _http = httpClient ?? http.Client();

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
      final result = await _authenticate(server, base);
      if (result is ApiSuccess<XtreamSession>) return result;
      // Credenciais recusadas: outro DNS do mesmo painel não vai mudar isso.
      if (result is ApiError<XtreamSession>) return result;
      last = result;
    }
    return last ?? const ApiBadPayload<XtreamSession>('Servidor sem endereço.');
  }

  @override
  Future<ApiResult<List<XtreamCategory>>> categories(
    XtreamSession session,
    XtreamSection section,
  ) async {
    final uri = _playerApi(session.baseUri, session.server, {'action': section.action});
    final result = await _getJson(uri, listTimeout);
    if (result is! ApiSuccess<Object?>) {
      return _fail<List<XtreamCategory>>(result);
    }
    final data = result.data;
    if (data is! List<dynamic>) {
      return const ApiBadPayload<List<XtreamCategory>>('Lista de categorias inesperada.');
    }
    try {
      return ApiSuccess<List<XtreamCategory>>(
        data
            .map((e) => XtreamCategory.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } on TypeError {
      return const ApiBadPayload<List<XtreamCategory>>('Categoria com formato inesperado.');
    }
  }

  @override
  Future<ApiResult<List<XtreamChannel>>> liveStreams(
    XtreamSession session,
    String categoryId,
  ) async {
    final uri = _playerApi(session.baseUri, session.server, {
      'action': 'get_live_streams',
      'category_id': categoryId,
    });
    final result = await _getJson(uri, listTimeout);
    if (result is! ApiSuccess<Object?>) {
      return _fail<List<XtreamChannel>>(result);
    }
    final data = result.data;
    if (data is! List<dynamic>) {
      return const ApiBadPayload<List<XtreamChannel>>('Lista de canais inesperada.');
    }
    try {
      return ApiSuccess<List<XtreamChannel>>(
        data
            .map((e) => XtreamChannel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } on TypeError {
      return const ApiBadPayload<List<XtreamChannel>>('Canal com formato inesperado.');
    }
  }

  @override
  Future<ApiResult<List<XtreamMovie>>> vodStreams(
    XtreamSession session,
    String categoryId,
  ) =>
      _listOf(session, 'get_vod_streams', {'category_id': categoryId},
          XtreamMovie.fromJson, 'filmes');

  @override
  Future<ApiResult<List<XtreamSeries>>> seriesList(
    XtreamSession session,
    String categoryId,
  ) =>
      _listOf(session, 'get_series', {'category_id': categoryId},
          XtreamSeries.fromJson, 'séries');

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
      return ApiSuccess<List<T>>([
        for (final e in data) parse(e as Map<String, dynamic>),
      ]);
    } on TypeError {
      return ApiBadPayload<List<T>>('Item de $label com formato inesperado.');
    }
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

  Future<ApiResult<Object?>> _getJson(Uri uri, Duration timeout) async {
    try {
      final response = await _http.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        return ApiNetworkError<Object?>('HTTP ${response.statusCode}');
      }
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      try {
        return ApiSuccess<Object?>(jsonDecode(body));
      } on FormatException {
        return const ApiBadPayload<Object?>('Resposta não é JSON.');
      }
    } on TimeoutException {
      return ApiTimeout<Object?>();
    } on Exception catch (e) {
      // Só o tipo: a mensagem da exceção pode conter a URL com a senha.
      return ApiNetworkError<Object?>(e.runtimeType.toString());
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
