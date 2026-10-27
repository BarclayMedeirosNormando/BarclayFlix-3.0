import 'dart:io';

import 'package:barclayflix/core/network/dns_fallback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAnswer', () {
    test('lê o primeiro endereço IPv4 da resposta', () {
      const body = '{"Status":0,"Answer":[{"name":"x.","type":5,"data":"y."},'
          '{"name":"y.","type":1,"TTL":300,"data":"38.183.188.72"}]}';
      expect(DnsFallback.parseAnswer(body)?.address, '38.183.188.72');
    });

    test('ignora endereço de bloqueio, resposta vazia e texto inválido', () {
      expect(DnsFallback.parseAnswer('{"Answer":[{"type":1,"data":"0.0.0.0"}]}'), isNull);
      expect(DnsFallback.parseAnswer('{"Status":3}'), isNull);
      expect(DnsFallback.parseAnswer('não é json'), isNull);
    });
  });

  test('isSinkhole reconhece 0.0.0.0 e loopback, mas não um IP público', () {
    expect(DnsFallback.isSinkhole(InternetAddress('0.0.0.0')), isTrue);
    expect(DnsFallback.isSinkhole(InternetAddress('127.0.0.1')), isTrue);
    expect(DnsFallback.isSinkhole(InternetAddress('38.183.188.72')), isFalse);
  });

  group('forPlayback', () {
    test('com o nome bloqueado troca pelo IP e manda o Host', () async {
      final dns = DnsFallback(resolver: (_) async => InternetAddress('1.2.3.4'));

      final t = await dns.forPlayback(Uri.parse('http://p2bras.xyz:8080/live/u/p/1.ts'));

      expect(t.url.toString(), 'http://1.2.3.4:8080/live/u/p/1.ts');
      expect(t.headers, {'Host': 'p2bras.xyz:8080'});
    });

    test('com o DNS funcionando a URL não muda', () async {
      final dns = DnsFallback(resolver: (_) async => null);

      final t = await dns.forPlayback(Uri.parse('http://tvplay.xyz/live/u/p/1.ts'));

      expect(t.url.toString(), 'http://tvplay.xyz/live/u/p/1.ts');
      expect(t.headers, isNull);
    });

    test('https fica com o nome (o certificado precisa dele)', () async {
      final dns = DnsFallback(resolver: (_) async => InternetAddress('1.2.3.4'));

      final t = await dns.forPlayback(Uri.parse('https://p2bras.xyz/live/u/p/1.ts'));

      expect(t.url.host, 'p2bras.xyz');
      expect(t.headers, isNull);
    });
  });

  test('overrideFor guarda a resposta e não consulta de novo', () async {
    var calls = 0;
    final dns = DnsFallback(resolver: (_) async {
      calls++;
      return InternetAddress('1.2.3.4');
    });

    await dns.overrideFor('p2bras.xyz');
    await dns.overrideFor('p2bras.xyz');

    expect(calls, 1);
  });

  test('endereço que já é IP não passa pelo resolvedor', () async {
    var calls = 0;
    final dns = DnsFallback(resolver: (_) async {
      calls++;
      return InternetAddress('1.2.3.4');
    });

    expect(await dns.overrideFor('38.183.188.72'), isNull);
    expect(calls, 0);
  });
  test('TlsTrust só aceita certificado dos hosts liberados', () {
    TlsTrust.allow('Painel-Iptv.XYZ');

    expect(TlsTrust.accepts('painel-iptv.xyz'), isTrue);
    expect(TlsTrust.accepts('script.google.com'), isFalse);
  });
}
