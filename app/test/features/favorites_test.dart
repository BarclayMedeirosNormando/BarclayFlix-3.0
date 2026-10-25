import 'package:barclayflix/core/network/api_result.dart';
import 'package:barclayflix/features/auth/data/device_models.dart';
import 'package:barclayflix/features/favorites/data/favorites_repository.dart';
import 'package:barclayflix/features/xtream/data/xtream_client.dart';
import 'package:barclayflix/features/xtream/data/xtream_models.dart';
import 'package:barclayflix/features/xtream/state/server_session_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/unused_xtream.dart';

const _server = XtreamServer(
  id: 's1',
  apelido: 'TVPLAY',
  hosts: ['http://a.xyz'],
  username: 'u',
  password: 'p',
);

final _session = XtreamSession(
  server: _server,
  baseUri: Uri.parse('http://a.xyz'),
  userInfo: const XtreamUserInfo(
    authorized: true,
    status: 'Active',
    expiresAt: null,
    maxConnections: 1,
    activeConnections: 0,
    isTrial: false,
  ),
);

class _Api with UnusedXtreamMethods implements XtreamApi {
  @override
  Future<ApiResult<XtreamSession>> connect(XtreamServer server) async => ApiSuccess(_session);

  @override
  Future<ApiResult<List<XtreamCategory>>> categories(
    XtreamSession session,
    XtreamSection section,
  ) async =>
      const ApiSuccess<List<XtreamCategory>>([]);

  @override
  Future<ApiResult<List<XtreamChannel>>> liveStreams(
    XtreamSession session,
    String categoryId,
  ) async =>
      const ApiSuccess<List<XtreamChannel>>([]);
}

class _Favs implements FavoritesApi {
  _Favs({this.initial = const [], this.failSet = false});

  final List<FavoriteEntry> initial;
  final bool failSet;
  final calls = <String>[];

  @override
  Future<ApiResult<List<FavoriteEntry>>> load(String serverId) async =>
      ApiSuccess<List<FavoriteEntry>>(initial);

  @override
  Future<ApiResult<bool>> set(String serverId, FavoriteEntry entry, {required bool on}) async {
    calls.add('${on ? '+' : '-'}${entry.key}');
    return failSet ? const ApiError<bool>('BUSY', 'ocupado') : const ApiSuccess<bool>(true);
  }
}

const _movie = FavoriteEntry(type: FavoriteType.vod, id: '7', name: 'Filme A');

Future<ServerSessionProvider> _ready(_Favs favs) async {
  final p = ServerSessionProvider(_Api(), _server, favorites: favs);
  await p.connect();
  await p.loadFavorites();
  return p;
}

void main() {
  test('carrega a lista do servidor ao conectar', () async {
    final p = await _ready(_Favs(initial: const [_movie]));
    expect(p.favoritesLoaded, isTrue);
    expect(p.isFavorite(FavoriteType.vod, '7'), isTrue);
    expect(p.isFavorite(FavoriteType.live, '7'), isFalse);
  });

  test('liga e desliga um item, avisando o servidor', () async {
    final favs = _Favs();
    final p = await _ready(favs);

    expect(await p.toggleFavorite(_movie), isTrue);
    expect(p.isFavorite(FavoriteType.vod, '7'), isTrue);

    expect(await p.toggleFavorite(_movie), isFalse);
    expect(p.isFavorite(FavoriteType.vod, '7'), isFalse);

    expect(favs.calls, ['+vod:7', '-vod:7']);
  });

  test('desfaz a mudança quando o servidor recusa', () async {
    final p = await _ready(_Favs(failSet: true));
    expect(await p.toggleFavorite(_movie), isFalse);
    expect(p.isFavorite(FavoriteType.vod, '7'), isFalse);
  });

  test('o item mais recente fica primeiro', () async {
    final p = await _ready(_Favs());
    await p.toggleFavorite(_movie);
    await p.toggleFavorite(const FavoriteEntry(type: FavoriteType.live, id: '9', name: 'Canal'));
    expect(p.favorites.map((f) => f.key), ['live:9', 'vod:7']);
  });

  test('FavoriteEntry.fromJson ignora tipo desconhecido', () {
    expect(FavoriteEntry.fromJson({'item_type': 'x', 'item_id': '1'}), isNull);
    final f = FavoriteEntry.fromJson({'item_type': 'series', 'item_id': '3', 'name': 'S', 'image': ''});
    expect(f?.type, FavoriteType.series);
    expect(f?.imageUrl, isNull);
  });
}
