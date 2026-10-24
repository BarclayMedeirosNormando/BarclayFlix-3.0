import 'dart:convert';

import 'package:barclayflix/core/network/api_client.dart';
import 'package:barclayflix/core/network/api_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ApiClient clientWith(
  Future<http.Response> Function(http.Request) handler, {
  Duration timeout = const Duration(seconds: 1),
  int attempts = 1,
}) =>
    ApiClient(
      baseUrl: 'https://example.com/exec',
      appVersion: '3.0.0',
      httpClient: MockClient(handler),
      timeout: timeout,
      maxAttempts: attempts,
      retryDelay: Duration.zero,
    );

http.Response jsonResponse(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

String parseValue(JsonMap data) => data['value'] as String;

void main() {
  test('envia action, schema, app_version e parâmetros na query', () async {
    late Uri sent;
    final client = clientWith((req) async {
      sent = req.url;
      return jsonResponse({'schema': 1, 'ok': true, 'data': {'value': 'x'}});
    });

    await client.call('check_device', {'device_id': 'abc'}, parseValue);

    expect(sent.queryParameters['action'], 'check_device');
    expect(sent.queryParameters['schema'], '1');
    expect(sent.queryParameters['app_version'], '3.0.0');
    expect(sent.queryParameters['device_id'], 'abc');
  });

  test('ok:true devolve ApiSuccess com os dados convertidos', () async {
    final client = clientWith((_) async =>
        jsonResponse({'schema': 1, 'ok': true, 'data': {'value': 'ola'}}));

    final r = await client.call('health', {}, parseValue);

    expect(r, isA<ApiSuccess<String>>());
    expect(r.dataOrNull, 'ola');
  });

  test('ok:false devolve ApiError com o código', () async {
    final client = clientWith((_) async => jsonResponse({
          'schema': 1,
          'ok': false,
          'error': {'code': 'SCHEMA_ERROR', 'message': 'Aba ausente: Clientes'},
        }));

    final r = await client.call('health', {}, parseValue);

    expect(r, isA<ApiError<String>>());
    expect((r as ApiError<String>).code, 'SCHEMA_ERROR');
    expect(r.failureMessage, contains('planilha'));
  });

  test('corpo HTML vira ApiBadPayload', () async {
    final client =
        clientWith((_) async => http.Response('<html>erro</html>', 200));

    final r = await client.call('health', {}, parseValue);

    expect(r, isA<ApiBadPayload<String>>());
  });

  test('campo ausente na conversão vira ApiBadPayload', () async {
    final client = clientWith((_) async =>
        jsonResponse({'schema': 1, 'ok': true, 'data': <String, dynamic>{}}));

    final r = await client.call('health', {}, parseValue);

    expect(r, isA<ApiBadPayload<String>>());
  });

  test('HTTP diferente de 200 vira ApiNetworkError', () async {
    final client = clientWith((_) async => http.Response('x', 500));

    final r = await client.call('health', {}, parseValue);

    expect(r, isA<ApiNetworkError<String>>());
  });

  test('estouro de tempo vira ApiTimeout', () async {
    final client = clientWith(
      (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return jsonResponse({'schema': 1, 'ok': true, 'data': {'value': 'x'}});
      },
      timeout: const Duration(milliseconds: 50),
    );

    final r = await client.call('health', {}, parseValue);

    expect(r, isA<ApiTimeout<String>>());
  });

  test('rede com falha tenta de novo até maxAttempts', () async {
    var calls = 0;
    final client = clientWith(
      (_) async {
        calls++;
        throw http.ClientException('sem rede');
      },
      attempts: 3,
    );

    final r = await client.call('health', {}, parseValue);

    expect(r, isA<ApiNetworkError<String>>());
    expect(calls, 3);
  });

  test('BUSY é repetido e depois dá sucesso', () async {
    var calls = 0;
    final client = clientWith(
      (_) async {
        calls++;
        if (calls == 1) {
          return jsonResponse({
            'schema': 1,
            'ok': false,
            'error': {'code': 'BUSY', 'message': ''},
          });
        }
        return jsonResponse({'schema': 1, 'ok': true, 'data': {'value': 'ok'}});
      },
      attempts: 3,
    );

    final r = await client.call('health', {}, parseValue);

    expect(r.dataOrNull, 'ok');
    expect(calls, 2);
  });

  test('erro de API que não é BUSY não é repetido', () async {
    var calls = 0;
    final client = clientWith(
      (_) async {
        calls++;
        return jsonResponse({
          'schema': 1,
          'ok': false,
          'error': {'code': 'BAD_REQUEST', 'message': 'x'},
        });
      },
      attempts: 3,
    );

    await client.call('health', {}, parseValue);

    expect(calls, 1);
  });
}
