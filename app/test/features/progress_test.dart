import 'package:barclayflix/core/network/api_result.dart';
import 'package:barclayflix/features/auth/data/device_models.dart';
import 'package:barclayflix/features/player/data/play_item.dart';
import 'package:barclayflix/features/progress/data/progress_repository.dart';
import 'package:barclayflix/features/xtream/data/xtream_client.dart';
import 'package:barclayflix/features/xtream/data/xtream_models.dart';
import 'package:barclayflix/features/xtream/state/server_session_provider.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _Api implements XtreamApi {
  @override
  Future<ApiResult<XtreamSession>> connect(XtreamServer server) async =>
      ApiSuccess(_session);

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

  @override
  Future<ApiResult<List<XtreamMovie>>> vodStreams(
    XtreamSession session,
    String categoryId,
  ) async =>
      const ApiSuccess<List<XtreamMovie>>([]);

  @override
  Future<ApiResult<List<XtreamSeries>>> seriesList(
    XtreamSession session,
    String categoryId,
  ) async =>
      const ApiSuccess<List<XtreamSeries>>([]);

  @override
  Future<ApiResult<XtreamSeriesDetail>> seriesInfo(
    XtreamSession session,
    String seriesId,
  ) async =>
      const ApiSuccess<XtreamSeriesDetail>(XtreamSeriesDetail(
        name: 'Série A',
        seasons: {
          1: [
            XtreamEpisode(
              id: '101',
              season: 1,
              number: 3,
              title: 'Três',
              extension: 'mkv',
            ),
          ],
        },
      ));

  @override
  Future<ApiResult<List<EpgEntry>>> shortEpg(
    XtreamSession session,
    String streamId,
  ) async =>
      const ApiSuccess<List<EpgEntry>>([]);

  @override
  Future<ApiResult<XtreamVodInfo>> vodInfo(
    XtreamSession session,
    String vodId,
  ) async =>
      ApiSuccess<XtreamVodInfo>(XtreamVodInfo(
        id: vodId,
        name: 'Filme $vodId',
        extension: 'mp4',
        imageUrl: 'http://img.xyz/$vodId.jpg',
      ));
}

class _Progress implements ProgressApi {
  _Progress(this.stored);

  final List<ProgressEntry> stored;
  final List<ProgressEntry> saved = [];

  @override
  Future<ApiResult<List<ProgressEntry>>> load(String serverId) async =>
      ApiSuccess<List<ProgressEntry>>(stored);

  @override
  Future<ApiResult<bool>> save(String serverId, ProgressEntry entry) async {
    saved.add(entry);
    return const ApiSuccess<bool>(true);
  }
}

Future<ServerSessionProvider> _ready(_Progress progress) async {
  final p = ServerSessionProvider(_Api(), _server, progress: progress);
  await p.connect();
  // connect() não espera o loadContinue; aguarda de novo (é idempotente).
  await p.loadContinue(force: true);
  return p;
}

void main() {
  test('ProgressEntry lê campos e calcula a fração assistida', () {
    final e = ProgressEntry.fromJson({
      'item_type': 'vod',
      'item_id': 1234,
      'position_s': '1830',
      'duration_s': 5400,
    });
    expect(e.key, 'vod:1234');
    expect(e.positionS, 1830);
    expect(e.fraction, closeTo(0.339, 0.001));
    expect(
      const ProgressEntry(type: 'vod', id: '1', positionS: 5, durationS: 0).fraction,
      0,
    );
  });

  test('continuar assistindo resolve título e retoma da posição salva', () async {
    final p = await _ready(_Progress(const [
      ProgressEntry(type: 'vod', id: '7', positionS: 600, durationS: 3000),
      ProgressEntry(type: 'episode', id: '5:101', positionS: 300, durationS: 1500),
    ]));

    final list = p.continueWatching;
    expect(list, hasLength(2));
    expect(list[0].item.title, 'Filme 7');
    expect(list[0].item.startAt, const Duration(seconds: 600));
    expect(list[0].item.url.toString(), 'http://a.xyz/movie/u/p/7.mp4');
    expect(list[0].fraction, closeTo(0.2, 0.001));
    expect(list[1].item.title, contains('Série A'));
    expect(list[1].item.url.toString(), 'http://a.xyz/series/u/p/101.mkv');
    expect(list[1].item.progressId, '5:101');
  });

  test('itens quase terminados ou recém-começados não entram na fileira', () async {
    final p = await _ready(_Progress(const [
      ProgressEntry(type: 'vod', id: '1', positionS: 2900, durationS: 3000),
      ProgressEntry(type: 'vod', id: '2', positionS: 3, durationS: 3000),
      ProgressEntry(type: 'vod', id: '3', positionS: 100, durationS: 3000),
    ]));

    expect(p.continueWatching.map((e) => e.item.progressId), ['3']);
  });

  test('recordProgress salva, ignora canais e coloca o item em primeiro', () async {
    final progress = _Progress(const [
      ProgressEntry(type: 'vod', id: '7', positionS: 600, durationS: 3000),
    ]);
    final p = await _ready(progress);

    PlayItem movie(String id) => PlayItem(
          title: 'Filme $id',
          url: Uri.parse('http://a.xyz/movie/u/p/$id.mp4'),
          kind: PlayKind.vod,
          progressId: id,
        );

    p.recordProgress(movie('8'), const Duration(seconds: 120), const Duration(seconds: 4000));
    p.recordProgress(movie('9'), const Duration(seconds: 2), const Duration(seconds: 4000));
    p.recordProgress(
      PlayItem(
        title: 'Canal',
        url: Uri.parse('http://a.xyz/live/u/p/1.ts'),
        kind: PlayKind.live,
      ),
      const Duration(seconds: 120),
      const Duration(seconds: 4000),
    );

    expect(progress.saved.map((e) => e.id), ['8']);
    expect(progress.saved.single.positionS, 120);
    expect(p.continueWatching.map((e) => e.item.progressId), ['8', '7']);
  });
}
