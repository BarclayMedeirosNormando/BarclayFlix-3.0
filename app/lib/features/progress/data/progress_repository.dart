import '../../../core/device/device_identity.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';

/// Posição de reprodução de um item (`get_progress` / `save_progress`).
class ProgressEntry {
  const ProgressEntry({
    required this.type,
    required this.id,
    required this.positionS,
    required this.durationS,
  });

  factory ProgressEntry.fromJson(JsonMap j) => ProgressEntry(
        type: '${j['item_type']}',
        id: '${j['item_id']}',
        positionS: int.tryParse('${j['position_s'] ?? ''}') ?? 0,
        durationS: int.tryParse('${j['duration_s'] ?? ''}') ?? 0,
      );

  /// `vod` ou `episode`.
  final String type;

  /// Filme: id do stream. Episódio: `<idDaSérie>:<idDoEpisódio>`.
  final String id;
  final int positionS;
  final int durationS;

  String get key => '$type:$id';

  /// 0.0 a 1.0 (0 quando a duração é desconhecida).
  double get fraction => durationS <= 0 ? 0 : (positionS / durationS).clamp(0.0, 1.0);
}

/// Contrato mínimo usado pelo estado do app (facilita testes).
abstract interface class ProgressApi {
  Future<ApiResult<List<ProgressEntry>>> load(String serverId);

  Future<ApiResult<bool>> save(String serverId, ProgressEntry entry);
}

/// Sem backend de progresso (testes e fallback): nada é salvo nem lido.
class NullProgressApi implements ProgressApi {
  const NullProgressApi();

  @override
  Future<ApiResult<List<ProgressEntry>>> load(String serverId) async =>
      const ApiSuccess<List<ProgressEntry>>([]);

  @override
  Future<ApiResult<bool>> save(String serverId, ProgressEntry entry) async =>
      const ApiSuccess<bool>(true);
}

/// Progresso guardado pela API v1 (planilha hoje, Supabase depois).
class ProgressRepository implements ProgressApi {
  ProgressRepository(this._api, this._identity);

  final ApiClient _api;
  final DeviceIdentity _identity;

  @override
  Future<ApiResult<List<ProgressEntry>>> load(String serverId) async {
    final deviceId = await _identity.getOrCreate();
    return _api.call<List<ProgressEntry>>(
      'get_progress',
      {'device_id': deviceId, 'servidor_id': serverId},
      (data) => [
        for (final e in (data['items'] as List<dynamic>? ?? const []))
          ProgressEntry.fromJson(e as Map<String, dynamic>),
      ],
    );
  }

  @override
  Future<ApiResult<bool>> save(String serverId, ProgressEntry entry) async {
    final deviceId = await _identity.getOrCreate();
    return _api.call<bool>(
      'save_progress',
      {
        'device_id': deviceId,
        'servidor_id': serverId,
        'item_type': entry.type,
        'item_id': entry.id,
        'position_s': '${entry.positionS}',
        'duration_s': '${entry.durationS}',
      },
      (_) => true,
    );
  }
}
