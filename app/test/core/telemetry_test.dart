import 'dart:convert';

import 'package:barclayflix/core/device/device_identity.dart';
import 'package:barclayflix/core/network/api_client.dart';
import 'package:barclayflix/core/telemetry/telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Id extends DeviceIdentity {
  @override
  Future<String> getOrCreate() async => 'aaaaaaaa-1111';
}

TelemetryEvent _ev(String name, {String session = 's1', int v1 = 0}) => TelemetryEvent(
      session: session,
      serverId: 'S1',
      name: name,
      type: 'live',
      itemId: '42',
      title: 'Globo HD',
      v1: v1,
    );

ApiClient _client(http.Client c) => ApiClient(
      baseUrl: 'https://example.test/exec',
      appVersion: '3.0.5',
      httpClient: c,
      maxAttempts: 1,
      retryDelay: Duration.zero,
    );

const _okBody = '{"schema":1,"ok":true,"data":{"accepted":1}}';

void main() {
  test('envia eventos em lotes compactos pela ação log_event', () async {
    final calls = <Uri>[];
    final svc = TelemetryService(
      _client(MockClient((req) async {
        calls.add(req.url);
        return http.Response(_okBody, 200);
      })),
      _Id(),
    );
    for (var i = 0; i < 7; i++) {
      svc.log(_ev(i == 0 ? 'start' : 'hb', v1: i));
    }
    await svc.flush();

    expect(calls, hasLength(2)); // 5 + 2
    expect(calls.first.queryParameters['action'], 'log_event');
    expect(calls.first.queryParameters['device_id'], 'aaaaaaaa-1111');
    final first = jsonDecode(calls.first.queryParameters['e']!) as List<dynamic>;
    expect(first, hasLength(5));
    final row = first.first as List<dynamic>;
    // [idadeMs, sessao, servidor, evento, tipo, itemId, nome, v1, v2, detalhe]
    expect(row[1], 's1');
    expect(row[2], 'S1');
    expect(row[3], 'start');
    expect(row[4], 'live');
    expect(row[5], '42');
    expect(row[6], 'Globo HD');
    expect(svc.pending, 0);
    svc.dispose();
  });

  test('falha de rede mantém os eventos para o próximo ciclo', () async {
    var fail = true;
    final svc = TelemetryService(
      _client(MockClient((req) async {
        if (fail) throw http.ClientException('sem internet');
        return http.Response(_okBody, 200);
      })),
      _Id(),
    );
    svc.log(_ev('start'));
    svc.log(_ev('ok'));
    await svc.flush();
    expect(svc.pending, 2);

    fail = false;
    await svc.flush();
    expect(svc.pending, 0);
    svc.dispose();
  });

  test('recusa da API (backend antigo) descarta o lote', () async {
    final svc = TelemetryService(
      _client(MockClient((req) async => http.Response(
            '{"schema":1,"ok":false,"error":{"code":"BAD_REQUEST","message":"Ação desconhecida"}}',
            200,
          ))),
      _Id(),
    );
    svc.log(_ev('start'));
    await svc.flush();
    expect(svc.pending, 0);
    svc.dispose();
  });

  test('servidor ocupado (BUSY) mantém os eventos', () async {
    final svc = TelemetryService(
      _client(MockClient((req) async => http.Response(
            '{"schema":1,"ok":false,"error":{"code":"BUSY","message":"ocupado"}}',
            200,
          ))),
      _Id(),
    );
    svc.log(_ev('start'));
    await svc.flush();
    expect(svc.pending, 1);
    svc.dispose();
  });

  test('buffer cheio descarta os mais antigos', () {
    final svc = TelemetryService(
      _client(MockClient((req) async => http.Response(_okBody, 200))),
      _Id(),
      maxBuffer: 3,
    );
    for (var i = 0; i < 10; i++) {
      svc.log(_ev('hb', v1: i));
    }
    expect(svc.pending, 3);
    svc.dispose();
  });

  test('nome longo é cortado e a idade do evento é calculada no envio', () {
    final e = TelemetryEvent(
      session: 's',
      serverId: 'S1',
      name: 'start',
      type: 'vod',
      title: 'x' * 200,
      at: DateTime.now().subtract(const Duration(seconds: 30)),
    );
    final wire = e.toWire(DateTime.now());
    expect((wire[6] as String).length, 50);
    expect(wire[0] as int, greaterThanOrEqualTo(29000));
  });

  test('NullTelemetry não faz nada', () async {
    const t = NullTelemetry();
    t.log(_ev('start'));
    await t.flush();
  });
}
