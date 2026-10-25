import 'dart:convert';

import 'package:barclayflix/core/cache/list_cache.dart';
import 'package:barclayflix/core/device/device_identity.dart';
import 'package:barclayflix/core/device/platform_kind.dart';
import 'package:barclayflix/core/network/api_client.dart';
import 'package:barclayflix/core/network/api_result.dart';
import 'package:barclayflix/core/text.dart';
import 'package:barclayflix/features/auth/data/auth_repository.dart';
import 'package:barclayflix/features/auth/data/device_models.dart';
import 'package:barclayflix/features/xtream/data/xtream_client.dart';
import 'package:barclayflix/features/xtream/data/xtream_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemCache implements ListCache {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String text) async => data[key] = text;
}

class _Snap implements ActiveSnapshotStore {
  String? json;
  DateTime? at;

  @override
  Future<void> save(String j) async {
    json = j;
    at = DateTime.now();
  }

  @override
  Future<({String json, DateTime savedAt})?> load() async =>
      json == null ? null : (json: json!, savedAt: at!);
}

class _Id implements DeviceIdentity {
  @override
  Future<String> getOrCreate() async => 'abcdef12-0000-0000-0000-000000000000';
}

const _server = XtreamServer(
  id: 's1',
  apelido: 'TV',
  hosts: ['http://a.xyz'],
  username: 'u',
  password: 'p',
);

final _session = XtreamSession(
  server: _server,
  baseUri: Uri.parse('http://a.xyz'),
  userInfo: const XtreamUserInfo(
    authorized: true,
    status: 'Active',
    expiresAt: null,
    maxConnections: 1,
    activeConnections: 0,
    isTrial: false,
  ),
);

void main() {
  test('normalizeForSearch: caminho rápido (ASCII) e com acentos', () {
    expect(normalizeForSearch('  BBB 26  '), 'bbb 26');
    expect(normalizeForSearch('Ação Épica'), 'acao epica');
  });

  test('lista de filmes é guardada em disco e lida de volta ordenada por mais recente', () async {
    final cache = _MemCache();
    final client = XtreamClient(
      cache: cache,
      httpClient: MockClient((req) async => http.Response(
            jsonEncode([
              {'stream_id': 1, 'name': 'Velho', 'added': '100'},
              {'stream_id': 2, 'name': 'Novo', 'added': '900'},
            ]),
            200,
          )),
    );
    final r = await client.vodStreams(_session, '');
    expect((r as ApiSuccess<List<XtreamMovie>>).data.first.name, 'Novo');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cache.data.keys, contains('s1_get_vod_streams_all'));

    final cached = await client.cachedMovies(_session, '');
    expect(cached!.map((m) => m.name), ['Novo', 'Velho']);
    expect(await client.cachedMovies(_session, '99'), isNull);
  });

  test('sem internet, usa a última resposta "ativo" dentro do prazo', () async {
    final snap = _Snap();
    var online = true;
    final api = ApiClient(
      baseUrl: 'https://script.example/exec',
      appVersion: '3.0.3',
      retryDelay: Duration.zero,
      httpClient: MockClient((req) async {
        if (!online) throw http.ClientException('sem rede');
        return http.Response(
          jsonEncode({
            'schema': 1,
            'ok': true,
            'data': {
              'status': 'ativo',
              'activation_code': 'AAAA-BBBB',
              'expira_em': '2999-01-01',
              'servidores': [],
            },
          }),
          200,
        );
      }),
    );
    final repo = AuthRepository(api, _Id(), AppPlatform.android, snapshot: snap);

    final first = await repo.checkDevice();
    expect((first as ApiSuccess<DeviceCheck>).data.status, DeviceStatus.ativo);
    expect(snap.json, isNotNull);

    online = false;
    final offline = await repo.checkDevice();
    expect(offline, isA<ApiSuccess<DeviceCheck>>());

    snap.at = DateTime.now().subtract(const Duration(hours: 13));
    final tooOld = await repo.checkDevice();
    expect(tooOld, isNot(isA<ApiSuccess<DeviceCheck>>()));
  });
}
