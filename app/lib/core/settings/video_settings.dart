import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Preferências de desempenho guardadas no aparelho.
///
/// - **Modo compatibilidade de vídeo**: desliga a decodificação por hardware
///   (hwdec=no). Corrige travas em TVs/boxes cujo decodificador abre o vídeo
///   mas solta quadros. Usa mais CPU.
/// - **Modo leve**: menos efeitos visuais (degradês, animações) e menos memória
///   para vídeo e imagens. Ajuda aparelhos fracos.
///
/// Na primeira abertura, aparelhos Android antigos (sem suporte a 64 bits,
/// como TVs de 32 bits) já começam com os dois modos ligados.
class VideoSettings {
  VideoSettings._();

  static final ValueNotifier<bool> compat = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> lite = ValueNotifier<bool>(false);

  static const _compatKey = 'video_compat';
  static const _liteKey = 'perf_lite';
  static const _storage = FlutterSecureStorage();
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final c = await _storage.read(key: _compatKey);
      final l = await _storage.read(key: _liteKey);
      if (l == null) {
        // Primeira vez com esta versão: decide pelo aparelho.
        final weak = await _isWeakDevice();
        compat.value = c == null ? weak : c == '1';
        lite.value = weak;
        await _storage.write(key: _liteKey, value: lite.value ? '1' : '0');
        if (c == null) await _storage.write(key: _compatKey, value: compat.value ? '1' : '0');
      } else {
        compat.value = c == '1';
        lite.value = l == '1';
      }
    } catch (_) {
      // Sem armazenamento (ex.: testes): segue com o padrão (desligado).
    }
    _loaded = true;
  }

  /// Android sem 64 bits (TV/box antigo): costuma ter pouca memória e CPU fraca.
  static Future<bool> _isWeakDevice() async {
    try {
      if (!Platform.isAndroid) return false;
      final info = await DeviceInfoPlugin().androidInfo;
      return info.supported64BitAbis.isEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setCompat(bool value) async {
    compat.value = value;
    try {
      await _storage.write(key: _compatKey, value: value ? '1' : '0');
    } catch (_) {}
  }

  static Future<void> setLite(bool value) async {
    lite.value = value;
    try {
      await _storage.write(key: _liteKey, value: value ? '1' : '0');
    } catch (_) {}
  }
}
