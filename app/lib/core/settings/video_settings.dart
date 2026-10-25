import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Preferências de vídeo guardadas no aparelho.
///
/// "Modo compatibilidade de vídeo" desliga a decodificação por hardware
/// (hwdec=no): corrige travas/engasgos em TVs e boxes cujo decodificador de
/// hardware abre o vídeo mas solta quadros. Usa mais CPU, por isso é opcional.
class VideoSettings {
  VideoSettings._();

  static final ValueNotifier<bool> compat = ValueNotifier<bool>(false);

  static const _key = 'video_compat';
  static const _storage = FlutterSecureStorage();
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      compat.value = (await _storage.read(key: _key)) == '1';
    } catch (_) {
      // Sem armazenamento (ex.: testes): segue com o padrão (desligado).
    }
    _loaded = true;
  }

  static Future<void> setCompat(bool value) async {
    compat.value = value;
    try {
      await _storage.write(key: _key, value: value ? '1' : '0');
    } catch (_) {}
  }
}
