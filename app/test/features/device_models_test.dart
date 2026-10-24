import 'package:barclayflix/features/auth/data/device_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interpreta check_device ativo com servidores', () {
    final check = DeviceCheck.fromJson({
      'status': 'ativo',
      'activation_code': 'A3F9-21CD',
      'expira_em': '2026-12-01',
      'cliente': {'nome': 'Fulano'},
      'servidores': [
        {
          'id': 's1',
          'apelido': 'TVPLAY',
          'hosts': ['http://tvplypro.xyz', 'http://outro.xyz:8080'],
          'username': 'u',
          'password': 'p',
          'stream_format': 'm3u8',
        },
      ],
    });

    expect(check.status, DeviceStatus.ativo);
    expect(check.activationCode, 'A3F9-21CD');
    expect(check.expiraEm, DateTime(2026, 12, 1));
    expect(check.clienteNome, 'Fulano');
    expect(check.servers.single.hosts, hasLength(2));
    expect(check.servers.single.streamFormat, StreamFormat.m3u8);
  });

  test('nao_registrado traz só status e código', () {
    final check = DeviceCheck.fromJson({
      'status': 'nao_registrado',
      'activation_code': 'A3F9-21CD',
    });

    expect(check.status, DeviceStatus.naoRegistrado);
    expect(check.servers, isEmpty);
    expect(check.clienteNome, isNull);
  });

  test('stream_format ausente assume ts', () {
    final s = XtreamServer.fromJson({
      'id': 's1',
      'apelido': 'X',
      'hosts': ['http://a'],
      'username': 'u',
      'password': 'p',
    });

    expect(s.streamFormat, StreamFormat.ts);
  });

  test('status desconhecido lança FormatException', () {
    expect(
      () => DeviceCheck.fromJson({'status': 'xyz', 'activation_code': 'A'}),
      throwsFormatException,
    );
  });
}
