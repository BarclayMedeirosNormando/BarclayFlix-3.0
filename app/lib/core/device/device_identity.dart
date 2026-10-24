import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Identidade estável do dispositivo (UUID v4), guardada em armazenamento seguro.
/// O `device_id` funciona como credencial: não registrar em logs.
class DeviceIdentity {
  DeviceIdentity({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'device_id';
  final FlutterSecureStorage _storage;
  String? _cached;

  Future<String> getOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;

    String? id;
    try {
      id = await _storage.read(key: _key);
    } on Exception {
      id = null; // armazenamento corrompido: gera um novo
    }
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      try {
        await _storage.write(key: _key, value: id);
      } on Exception {
        // Sem persistência: o id vale só até fechar o app.
      }
    }
    return _cached = id;
  }
}
