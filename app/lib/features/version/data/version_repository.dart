import '../../../core/device/platform_kind.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';

/// Resposta de `check_version`.
class VersionInfo {
  const VersionInfo({
    required this.latest,
    required this.minSupported,
    required this.force,
    required this.updateUrl,
  });

  factory VersionInfo.fromJson(JsonMap j) => VersionInfo(
        latest: '${j['latest'] ?? ''}',
        minSupported: '${j['min_supported'] ?? ''}',
        force: j['force'] == true,
        updateUrl: '${j['update_url'] ?? ''}'.trim(),
      );

  /// Nenhuma exigência (rede indisponível, testes).
  static const none = VersionInfo(latest: '', minSupported: '', force: false, updateUrl: '');

  final String latest;
  final String minSupported;

  /// O servidor diz que esta versão é antiga demais para continuar.
  final bool force;
  final String updateUrl;
}

/// Compara versões `1.2.3`: negativo se a < b, 0 se iguais, positivo se a > b.
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.split('+').first.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
  final pa = parts(a);
  final pb = parts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

/// Contrato usado pelo estado do app (facilita testes).
abstract interface class VersionApi {
  Future<ApiResult<VersionInfo>> check();
}

/// Sem checagem de versão (testes e fallback).
class NullVersionApi implements VersionApi {
  const NullVersionApi();

  @override
  Future<ApiResult<VersionInfo>> check() async => const ApiSuccess<VersionInfo>(VersionInfo.none);
}

/// Pergunta à API v1 qual é a versão mais nova e a mínima aceita.
class VersionRepository implements VersionApi {
  VersionRepository(this._api, this._platform, this._version);

  final ApiClient _api;
  final AppPlatform _platform;
  final String _version;

  @override
  Future<ApiResult<VersionInfo>> check() => _api.call<VersionInfo>(
        'check_version',
        {'platform': _platform.apiName, 'version': _version},
        VersionInfo.fromJson,
      );
}
