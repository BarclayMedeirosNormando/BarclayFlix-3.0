import 'dart:io';

import 'package:barclayflix/features/version/data/app_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('abiToken', () {
    test('usa a primeira ABI conhecida', () {
      expect(abiToken(['arm64-v8a', 'armeabi-v7a', 'armeabi']), 'arm64-v8a');
      expect(abiToken(['armeabi-v7a', 'armeabi']), 'armeabi-v7a');
      expect(abiToken(['x86_64', 'x86']), 'x86_64');
    });
    test('armeabi vira 32 bits e desconhecido vira 64 bits', () {
      expect(abiToken(['armeabi']), 'armeabi-v7a');
      expect(abiToken(['mips']), 'arm64-v8a');
      expect(abiToken([]), 'arm64-v8a');
    });
  });

  test('resolveUpdateUrl troca {abi}', () {
    expect(resolveUpdateUrl('https://x/BarclayFlix-{abi}.apk', 'armeabi-v7a'),
        'https://x/BarclayFlix-armeabi-v7a.apk');
    expect(resolveUpdateUrl('https://x/a.apk', 'arm64-v8a'), 'https://x/a.apk');
  });

  group('AppUpdater', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('upd'));
    tearDown(() => dir.deleteSync(recursive: true));

    AppUpdater make(http.Client c, {List<String>? installed, String? installError}) => AppUpdater(
          client: c,
          tempDir: () async => dir,
          abi: () async => 'armeabi-v7a',
          install: (p) async {
            installed?.add(p);
            return installError;
          },
          isAndroid: true,
        );

    MockClient ok(List<int> body, {List<Uri>? seen}) => MockClient.streaming((req, _) async {
          seen?.add(req.url);
          return http.StreamedResponse(
            Stream.fromIterable([body.sublist(0, 1500), body.sublist(1500)]),
            200,
            contentLength: body.length,
          );
        });

    test('baixa, escolhe o APK da arquitetura e abre o instalador', () async {
      final body = List<int>.filled(3000, 7);
      final seen = <Uri>[];
      final installed = <String>[];
      final u = make(ok(body, seen: seen), installed: installed);
      await u.start('https://h/BarclayFlix-{abi}.apk');
      expect(seen.single.toString(), 'https://h/BarclayFlix-armeabi-v7a.apk');
      expect(installed, hasLength(1));
      expect(File(installed.single).lengthSync(), 3000);
      expect(u.phase, UpdatePhase.idle);
      expect(u.error, isNull);
    });

    test('HTTP 404 vira erro e não instala', () async {
      final installed = <String>[];
      final u = make(MockClient((_) async => http.Response('nope', 404)), installed: installed);
      await u.start('https://h/a.apk');
      expect(u.phase, UpdatePhase.error);
      expect(u.error, contains('404'));
      expect(installed, isEmpty);
    });

    test('página HTML pequena não é tratada como APK', () async {
      final installed = <String>[];
      final u = make(MockClient((_) async => http.Response('<html>', 200)), installed: installed);
      await u.start('https://h/a.apk');
      expect(u.phase, UpdatePhase.error);
      expect(installed, isEmpty);
    });

    test('erro do instalador aparece na tela', () async {
      final u = make(ok(List<int>.filled(3000, 1)), installError: 'sem permissão');
      await u.start('https://h/a.apk');
      expect(u.phase, UpdatePhase.error);
      expect(u.error, 'sem permissão');
    });

    test('falha de rede vira mensagem amigável', () async {
      final u = make(MockClient((_) async => throw const SocketException('x')));
      await u.start('https://h/a.apk');
      expect(u.phase, UpdatePhase.error);
      expect(u.error, contains('Tente de novo'));
    });

    test('fora do Android só abre o link', () async {
      String? opened;
      final u = AppUpdater(isAndroid: false, openLink: (url) async => opened = url);
      await u.start('https://h/win.zip');
      expect(opened, 'https://h/win.zip');
      expect(u.phase, UpdatePhase.idle);
    });
  });
}
