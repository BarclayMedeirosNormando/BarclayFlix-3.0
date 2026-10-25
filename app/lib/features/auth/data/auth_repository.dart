import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/device/device_identity.dart';
import '../../../core/device/platform_kind.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';
import 'device_models.dart';

/// Contrato mínimo que o estado de autenticação precisa (facilita testes).
abstract interface class DeviceChecker {
  Future<ApiResult<DeviceCheck>> checkDevice();
}

/// Guarda a última resposta "ativo" para o app seguir funcionando por algumas
/// horas se a API (Google) estiver fora do ar ou o aparelho sem internet.
abstract interface class ActiveSnapshotStore {
  Future<void> save(String json);

  /// JSON salvo e há quanto tempo, ou null.
  Future<({String json, DateTime savedAt})?> load();
}

class SecureSnapshotStore implements ActiveSnapshotStore {
  const SecureSnapshotStore();

  static const _storage = FlutterSecureStorage();
  static const _key = 'last_active_check';

  @override
  Future<void> save(String json) async {
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode({'at': DateTime.now().toIso8601String(), 'data': json}),
      );
    } catch (_) {}
  }

  @override
  Future<({String json, DateTime savedAt})?> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.tryParse('${m['at']}');
      final data = m['data'];
      if (at == null || data is! String) return null;
      return (json: data, savedAt: at);
    } catch (_) {
      return null;
    }
  }
}

/// Fala com a API v1 para ativação/validação do dispositivo.
class AuthRepository implements DeviceChecker {
  AuthRepository(
    this._api,
    this._identity,
    this._platform, {
    ActiveSnapshotStore? snapshot,
    this.grace = const Duration(hours: 12),
  }) : _snapshot = snapshot;

  final ApiClient _api;
  final DeviceIdentity _identity;
  final AppPlatform _platform;
  final ActiveSnapshotStore? _snapshot;

  /// Por quanto tempo vale a última resposta "ativo" quando a API não responde.
  final Duration grace;

  @override
  Future<ApiResult<DeviceCheck>> checkDevice() async {
    final deviceId = await _identity.getOrCreate();
    JsonMap? raw;
    final result = await _api.call<DeviceCheck>(
      'check_device',
      {'device_id': deviceId, 'platform': _platform.apiName},
      (json) {
        raw = json;
        return DeviceCheck.fromJson(json);
      },
    );

    final store = _snapshot;
    if (store == null) return result;

    // Resposta explícita do servidor: obedece (e guarda se estiver ativo).
    if (result is ApiSuccess<DeviceCheck>) {
      if (result.data.status == DeviceStatus.ativo && raw != null) {
        await store.save(jsonEncode(raw));
      }
      return result;
    }

    // Só falha de rede/tempo esgotado usa a última resposta "ativo".
    if (result is ApiNetworkError<DeviceCheck> || result is ApiTimeout<DeviceCheck>) {
      final saved = await store.load();
      if (saved != null && DateTime.now().difference(saved.savedAt) <= grace) {
        try {
          final check = DeviceCheck.fromJson(jsonDecode(saved.json) as Map<String, dynamic>);
          final exp = check.expiraEm;
          // A data de vencimento vale até o fim do dia.
          final expired = exp != null && exp.add(const Duration(days: 1)).isBefore(DateTime.now());
          if (check.status == DeviceStatus.ativo && !expired) return ApiSuccess(check);
        } catch (_) {}
      }
    }
    return result;
  }
}
