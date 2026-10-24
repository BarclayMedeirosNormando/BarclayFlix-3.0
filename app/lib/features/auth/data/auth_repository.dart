import '../../../core/device/device_identity.dart';
import '../../../core/device/platform_kind.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';
import 'device_models.dart';

/// Contrato mínimo que o estado de autenticação precisa (facilita testes).
abstract interface class DeviceChecker {
  Future<ApiResult<DeviceCheck>> checkDevice();
}

/// Fala com a API v1 para ativação/validação do dispositivo.
class AuthRepository implements DeviceChecker {
  AuthRepository(this._api, this._identity, this._platform);

  final ApiClient _api;
  final DeviceIdentity _identity;
  final AppPlatform _platform;

  @override
  Future<ApiResult<DeviceCheck>> checkDevice() async {
    final deviceId = await _identity.getOrCreate();
    return _api.call<DeviceCheck>(
      'check_device',
      {'device_id': deviceId, 'platform': _platform.apiName},
      DeviceCheck.fromJson,
    );
  }
}
