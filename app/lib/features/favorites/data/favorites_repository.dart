import '../../../core/device/device_identity.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';

/// Tipos de item da "Minha lista".
enum FavoriteType {
  live('live'),
  vod('vod'),
  series('series');

  const FavoriteType(this.wire);

  final String wire;

  static FavoriteType? parse(String s) {
    for (final t in values) {
      if (t.wire == s) return t;
    }
    return null;
  }
}

/// Um item da lista (guarda nome e imagem para mostrar sem consultar o servidor).
class FavoriteEntry {
  const FavoriteEntry({
    required this.type,
    required this.id,
    required this.name,
    this.imageUrl,
  });

  static FavoriteEntry? fromJson(JsonMap j) {
    final type = FavoriteType.parse('${j['item_type']}');
    final id = '${j['item_id'] ?? ''}';
    if (type == null || id.isEmpty) return null;
    final image = '${j['image'] ?? ''}'.trim();
    return FavoriteEntry(
      type: type,
      id: id,
      name: '${j['name'] ?? ''}',
      imageUrl: image.isEmpty ? null : image,
    );
  }

  final FavoriteType type;
  final String id;
  final String name;
  final String? imageUrl;

  String get key => '${type.wire}:$id';
}

/// Contrato usado pelo estado do app (facilita testes).
abstract interface class FavoritesApi {
  Future<ApiResult<List<FavoriteEntry>>> load(String serverId);

  Future<ApiResult<bool>> set(String serverId, FavoriteEntry entry, {required bool on});
}

/// Sem backend de favoritos (testes e fallback).
class NullFavoritesApi implements FavoritesApi {
  const NullFavoritesApi();

  @override
  Future<ApiResult<List<FavoriteEntry>>> load(String serverId) async =>
      const ApiSuccess<List<FavoriteEntry>>([]);

  @override
  Future<ApiResult<bool>> set(String serverId, FavoriteEntry entry, {required bool on}) async =>
      const ApiSuccess<bool>(true);
}

/// Favoritos guardados pela API v1: valem para todos os aparelhos do cliente.
class FavoritesRepository implements FavoritesApi {
  FavoritesRepository(this._api, this._identity);

  final ApiClient _api;
  final DeviceIdentity _identity;

  @override
  Future<ApiResult<List<FavoriteEntry>>> load(String serverId) async {
    final deviceId = await _identity.getOrCreate();
    return _api.call<List<FavoriteEntry>>(
      'get_favorites',
      {'device_id': deviceId, 'servidor_id': serverId},
      (data) => [
        for (final e in (data['items'] as List<dynamic>? ?? const []))
          if (FavoriteEntry.fromJson(e as Map<String, dynamic>) case final f?) f,
      ],
    );
  }

  @override
  Future<ApiResult<bool>> set(String serverId, FavoriteEntry entry, {required bool on}) async {
    final deviceId = await _identity.getOrCreate();
    return _api.call<bool>(
      'set_favorite',
      {
        'device_id': deviceId,
        'servidor_id': serverId,
        'item_type': entry.type.wire,
        'item_id': entry.id,
        'on': on ? '1' : '0',
        'name': entry.name,
        'image': entry.imageUrl ?? '',
      },
      (_) => true,
    );
  }
}
