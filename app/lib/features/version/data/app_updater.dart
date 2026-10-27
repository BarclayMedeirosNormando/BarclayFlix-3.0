import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Etapas da atualização feita dentro do app.
enum UpdatePhase { idle, downloading, installing, error }

/// Escolhe o APK certo: `arm64-v8a`, `armeabi-v7a` ou `x86_64`.
///
/// [supportedAbis] vem do Android, do mais preferido ao menos. Uma TV de CPU
/// 64 bits com sistema de 32 bits informa só ABIs de 32 bits, o que é o
/// correto para escolher o APK.
String abiToken(List<String> supportedAbis) {
  const known = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
  for (final abi in supportedAbis) {
    if (known.contains(abi)) return abi;
  }
  // `armeabi` (ARM antigo) roda o build de 32 bits.
  if (supportedAbis.contains('armeabi')) return 'armeabi-v7a';
  return 'arm64-v8a';
}

/// Troca `{abi}` no link pelo token da arquitetura. Links sem `{abi}` ficam iguais.
String resolveUpdateUrl(String template, String abi) => template.replaceAll('{abi}', abi);

Future<String> _defaultAbi() async {
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    return abiToken(info.supportedAbis);
  } on Exception {
    return 'arm64-v8a';
  }
}

Future<Directory> _defaultTempDir() => getTemporaryDirectory();

/// Abre o instalador do Android. Devolve `null` se abriu, ou a mensagem de erro.
Future<String?> _defaultInstall(String path) async {
  final result = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
  switch (result.type) {
    case ResultType.done:
      return null;
    case ResultType.permissionDenied:
      return 'Permita "Instalar apps desconhecidos" para o BarclayFlix nas configurações '
          'que abriram e toque em Atualizar de novo.';
    default:
      return 'Não foi possível abrir o instalador (${result.message}).';
  }
}

/// Baixa o APK da versão nova e abre o instalador do Android.
///
/// No Windows apenas abre o link no navegador. O Android sempre pede um toque
/// em "Instalar": instalação totalmente silenciosa não existe para apps comuns.
class AppUpdater extends ChangeNotifier {
  AppUpdater({
    http.Client? client,
    Future<Directory> Function()? tempDir,
    Future<String> Function()? abi,
    Future<String?> Function(String path)? install,
    Future<void> Function(String url)? openLink,
    bool? isAndroid,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _tempDir = tempDir ?? _defaultTempDir,
        _abi = abi ?? _defaultAbi,
        _install = install ?? _defaultInstall,
        _openLink = openLink ?? _defaultOpenLink,
        _isAndroid = isAndroid ?? Platform.isAndroid;

  final http.Client _client;
  final bool _ownsClient;
  final Future<Directory> Function() _tempDir;
  final Future<String> Function() _abi;
  final Future<String?> Function(String path) _install;
  final Future<void> Function(String url) _openLink;
  final bool _isAndroid;

  UpdatePhase _phase = UpdatePhase.idle;
  double? _progress;
  String? _error;
  bool _cancelled = false;
  bool _disposed = false;

  UpdatePhase get phase => _phase;

  /// 0..1, ou `null` quando o servidor não informa o tamanho.
  double? get progress => _progress;
  String? get error => _error;
  bool get busy => _phase == UpdatePhase.downloading || _phase == UpdatePhase.installing;

  /// Cancela o download em andamento.
  void cancel() {
    if (_phase == UpdatePhase.downloading) _cancelled = true;
  }

  Future<void> start(String urlTemplate) async {
    if (busy) return;
    if (!_isAndroid) {
      try {
        await _openLink(urlTemplate);
      } on Exception catch (e) {
        _fail('Não foi possível abrir o link ($e).');
      }
      return;
    }
    _cancelled = false;
    _error = null;
    _progress = null;
    _setPhase(UpdatePhase.downloading);
    File? file;
    try {
      final url = resolveUpdateUrl(urlTemplate, await _abi());
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) {
        _fail('Link de atualização inválido.');
        return;
      }
      final dir = await _tempDir();
      file = File('${dir.path}${Platform.pathSeparator}barclayflix-update.apk');
      if (file.existsSync()) file.deleteSync();

      final request = http.Request('GET', uri)
        ..headers['User-Agent'] = 'BarclayFlix-Updater'
        ..headers['Accept'] = '*/*';
      final response = await _client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        _fail('O servidor respondeu HTTP ${response.statusCode}. '
            'Confira o link da atualização.');
        return;
      }
      final total = response.contentLength;
      final sink = file.openWrite();
      var received = 0;
      var lastPercent = -1;
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          if (_cancelled) break;
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) {
            _progress = received / total;
            final percent = (_progress! * 100).floor();
            if (percent != lastPercent) {
              lastPercent = percent;
              _notify();
            }
          }
        }
      } finally {
        await sink.close();
      }
      if (_cancelled) {
        _deleteQuietly(file);
        _error = null;
        _progress = null;
        _setPhase(UpdatePhase.idle);
        return;
      }
      if (total != null && total > 0 && received != total) {
        _deleteQuietly(file);
        _fail('Download incompleto. Tente de novo.');
        return;
      }
      if (received < 1024) {
        // Página de erro/HTML em vez de APK.
        _deleteQuietly(file);
        _fail('O link não entregou um APK. Confira o link da atualização.');
        return;
      }
      _setPhase(UpdatePhase.installing);
      final problem = await _install(file.path);
      if (problem != null) {
        _fail(problem);
        return;
      }
      // O instalador do Android assumiu a tela; volta ao estado normal.
      _setPhase(UpdatePhase.idle);
    } on TimeoutException {
      if (file != null) _deleteQuietly(file);
      _fail('A conexão demorou demais. Tente de novo.');
    } on Exception catch (e) {
      if (file != null) _deleteQuietly(file);
      _fail('Falha ao atualizar (${e.runtimeType}). Tente de novo.');
    }
  }

  void _deleteQuietly(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } on Exception {
      // Arquivo temporário: ignorar.
    }
  }

  void _fail(String message) {
    _error = message;
    _progress = null;
    _setPhase(UpdatePhase.error);
  }

  void _setPhase(UpdatePhase p) {
    _phase = p;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsClient) _client.close();
    super.dispose();
  }
}

Future<void> _defaultOpenLink(String url) async {
  if (Platform.isWindows) {
    await Process.start('rundll32', ['url.dll,FileProtocolHandler', url]);
    return;
  }
  throw UnsupportedError('abrir link');
}
