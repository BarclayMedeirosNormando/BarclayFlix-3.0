import 'dart:convert';

import 'package:barclayflix/core/network/api_result.dart';
import 'package:barclayflix/features/auth/data/device_models.dart';
import 'package:barclayflix/features/xtream/data/xtream_client.dart';
import 'package:barclayflix/features/xtream/data/xtream_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

XtreamServer server([List<String> hosts = const ['http://a.xyz/']]) =>
    XtreamServer(
      id: 's1',
      apelido: 'TVPLAY',
      hosts: hosts,
      username: 'u',
      password: 'p',
    );

XtreamClient clientWith(Future<http.Response> Function(http.Request) handler) =>
    XtreamClient(
      httpClient: MockClient(handler),
      authTimeout: const Duration(seconds: 1),
      listTimeout: const Duration(seconds: 1),
    );

http.Response jsonResponse(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> authBody({
  Object auth = 1,
  Object? exp = '1765756800',
  Object maxCons = '1',
  Object activeCons = '0',
}) =>
    {
      'user_info': {
        'auth': auth,
        'status': 'Active',
        'exp_date': exp,
        'max_connections': maxCons,
        'active_cons': activeCons,
        'is_trial': '0',
      },
      'server_info': {'url': 'a.xyz'},
    };

void main() {
  test('normaliza host com barra final e chama player_api.php', () async {
    late Uri sent;
    final client = clientWith((req) async {
      sent = req.url;
      return jsonResponse(authBody());
    });

    final r = await client.connect(server());

    expect(r, isA<ApiSuccess<XtreamSession>>());
    expect(sent.host, 'a.xyz');
    expect(sent.path, '/player_api.php');
    expect(sent.queryParameters['username'], 'u');
    expect(sent.queryParameters['password'], 'p');
  });

  test('interpreta user_info (texto, números e data unix)', () async {
    final client = clientWith((_) async => jsonResponse(authBody()));

    final session = (await client.connect(server())).dataOrNull!;

    expect(session.baseUri.toString(), 'http://a.xyz');
    expect(session.userInfo.isActive, isTrue);
    expect(session.userInfo.maxConnections, 1);
    expect(session.userInfo.activeConnections, 0);
    expect(session.userInfo.isTrial, isFalse);
    expect(
      session.userInfo.expiresAt,
      DateTime.fromMillisecondsSinceEpoch(1765756800 * 1000),
    );
  });

  test('exp_date nulo ou vazio significa sem vencimento', () async {
    for (final exp in <Object?>[null, '', 'null', '0']) {
      final client = clientWith((_) async => jsonResponse(authBody(exp: exp)));
      final session = (await client.connect(server())).dataOrNull!;
      expect(session.userInfo.expiresAt, isNull, reason: 'exp_date=$exp');
    }
  });

  test('host sem esquema e com porta vira http://host:porta', () {
    expect(XtreamClient.baseUri('dns.xyz:8080').toString(), 'http://dns.xyz:8080');
    expect(XtreamClient.baseUri('  http://dns.xyz///').toString(), 'http://dns.xyz');
    expect(XtreamClient.baseUri(''), isNull);
  });

  test('tenta o próximo host quando o primeiro falha', () async {
    final hosts = <String>[];
    final client = clientWith((req) async {
      hosts.add(req.url.host);
      if (req.url.host == 'a.xyz') throw http.ClientException('sem rede');
      return jsonResponse(authBody());
    });

    final r = await client.connect(server(['http://a.xyz', 'http://b.xyz']));

    expect(hosts, ['a.xyz', 'b.xyz']);
    expect(r.dataOrNull?.baseUri.host, 'b.xyz');
  });

  test('credenciais recusadas (auth 0) não tentam outro host', () async {
    var calls = 0;
    final client = clientWith((_) async {
      calls++;
      return jsonResponse(authBody(auth: 0));
    });

    final r = await client.connect(server(['http://a.xyz', 'http://b.xyz']));

    expect(r, isA<ApiError<XtreamSession>>());
    expect((r as ApiError<XtreamSession>).code, 'AUTH_FAILED');
    expect(calls, 1);
  });

  test('todos os hosts fora do ar devolvem ApiNetworkError', () async {
    final client = clientWith((_) async => throw http.ClientException('x'));

    final r = await client.connect(server(['http://a.xyz', 'http://b.xyz']));

    expect(r, isA<ApiNetworkError<XtreamSession>>());
  });

  test('mensagem de erro de rede não vaza a senha', () async {
    final client = clientWith(
      (req) async => throw http.ClientException('falha em ${req.url}', req.url),
    );
    const comSenha = XtreamServer(
      id: 's1',
      apelido: 'TVPLAY',
      hosts: ['http://a.xyz'],
      username: 'usuario_x',
      password: 'segredo123',
    );

    final r = await client.connect(comSenha);

    final message = (r as ApiNetworkError<XtreamSession>).message;
    expect(message, isNot(contains('segredo123')));
    expect(message, isNot(contains('usuario_x')));
  });

  test('endereço vazio vira ApiBadPayload', () async {
    final client = clientWith((_) async => jsonResponse(authBody()));

    final r = await client.connect(server(['']));

    expect(r, isA<ApiBadPayload<XtreamSession>>());
  });

  test('lista categorias com id numérico ou texto', () async {
    late Uri sent;
    final client = clientWith((req) async {
      sent = req.url;
      if (req.url.queryParameters['action'] == null) {
        return jsonResponse(authBody());
      }
      return jsonResponse([
        {'category_id': '1', 'category_name': 'Filmes HD', 'parent_id': 0},
        {'category_id': 2, 'category_name': 'Esportes', 'parent_id': 0},
      ]);
    });
    final session = (await client.connect(server())).dataOrNull!;

    final r = await client.categories(session, XtreamSection.live);

    expect(sent.queryParameters['action'], 'get_live_categories');
    final items = r.dataOrNull!;
    expect(items.map((c) => c.id), ['1', '2']);
    expect(items.map((c) => c.name), ['Filmes HD', 'Esportes']);
  });

  test('categorias: resposta que não é lista vira ApiBadPayload', () async {
    final client = clientWith((req) async {
      if (req.url.queryParameters['action'] == null) {
        return jsonResponse(authBody());
      }
      return jsonResponse({'user_info': {'auth': 0}});
    });
    final session = (await client.connect(server())).dataOrNull!;

    final r = await client.categories(session, XtreamSection.vod);

    expect(r, isA<ApiBadPayload<List<XtreamCategory>>>());
  });
}
