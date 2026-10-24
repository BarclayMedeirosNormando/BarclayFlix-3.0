import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_result.dart';

/// Cliente HTTP da API v1 (Apps Script hoje, Supabase depois).
///
/// - Sempre GET, com `action`, `schema` e `app_version` na query.
/// - Timeout e retry apenas para rede/timeout/BUSY.
/// - Nunca lança exceção: devolve sempre um [ApiResult].
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.appVersion,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 2),
  })  : _base = Uri.parse(baseUrl),
        _http = httpClient ?? http.Client();

  /// Versão do contrato suportada por este app.
  static const int schema = 1;

  final String appVersion;
  final Duration timeout;
  final int maxAttempts;
  final Duration retryDelay;

  final Uri _base;
  final http.Client _http;

  /// Chama [action] e converte `data` com [parse].
  Future<ApiResult<T>> call<T>(
    String action,
    Map<String, String> params,
    T Function(JsonMap data) parse,
  ) async {
    var result = await _attempt(action, params);
    for (var i = 1; i < maxAttempts && _retryable(result); i++) {
      await Future<void>.delayed(retryDelay);
      result = await _attempt(action, params);
    }

    return switch (result) {
      ApiSuccess<JsonMap>(:final data) => _parse<T>(data, parse),
      ApiError<JsonMap>(:final code, :final message) => ApiError<T>(code, message),
      ApiNetworkError<JsonMap>(:final message) => ApiNetworkError<T>(message),
      ApiTimeout<JsonMap>() => ApiTimeout<T>(),
      ApiBadPayload<JsonMap>(:final message) => ApiBadPayload<T>(message),
    };
  }

  void dispose() => _http.close();

  bool _retryable(ApiResult<JsonMap> r) =>
      r is ApiNetworkError<JsonMap> ||
      r is ApiTimeout<JsonMap> ||
      (r is ApiError<JsonMap> && r.code == 'BUSY');

  Future<ApiResult<JsonMap>> _attempt(String action, Map<String, String> params) async {
    final uri = _base.replace(queryParameters: {
      ..._base.queryParameters,
      'action': action,
      'schema': '$schema',
      'app_version': appVersion,
      ...params,
    });

    try {
      final response = await _http.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        return ApiNetworkError<JsonMap>('HTTP ${response.statusCode}');
      }
      return _decode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on TimeoutException {
      return ApiTimeout<JsonMap>();
    } on Exception catch (e) {
      return ApiNetworkError<JsonMap>(e.toString());
    }
  }

  ApiResult<JsonMap> _decode(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return const ApiBadPayload<JsonMap>('Resposta não é JSON.');
    }
    if (json is! Map<String, dynamic>) {
      return const ApiBadPayload<JsonMap>('Resposta não é um objeto JSON.');
    }

    final ok = json['ok'];
    if (ok == true) {
      final data = json['data'];
      if (data is Map<String, dynamic>) return ApiSuccess<JsonMap>(data);
      return const ApiBadPayload<JsonMap>('Campo "data" ausente.');
    }
    if (ok == false) {
      final error = json['error'];
      if (error is Map<String, dynamic>) {
        return ApiError<JsonMap>(
          (error['code'] as String?) ?? 'INTERNAL',
          (error['message'] as String?) ?? '',
        );
      }
      return const ApiError<JsonMap>('INTERNAL', '');
    }
    return const ApiBadPayload<JsonMap>('Envelope sem o campo "ok".');
  }

  ApiResult<T> _parse<T>(JsonMap data, T Function(JsonMap data) parse) {
    try {
      return ApiSuccess<T>(parse(data));
    } on FormatException catch (e) {
      return ApiBadPayload<T>(e.message);
    } on TypeError catch (e) {
      return ApiBadPayload<T>('Campo inesperado: $e');
    }
  }
}
