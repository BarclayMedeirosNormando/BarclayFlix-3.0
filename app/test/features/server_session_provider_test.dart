import 'package:barclayflix/core/network/api_result.dart';
import 'package:barclayflix/features/auth/data/device_models.dart';
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

const _info = XtreamUserInfo(
  authorized: true,
  status: 'Active',
  expiresAt: null,
  maxConnections: 1,
  activeConnections: 0,
  isTrial: false,
);

final _session = XtreamSession(
  server: _server,
  baseUri: Uri.parse('http://a.xyz'),
  userInfo: _info,
);

class FakeXtream implements XtreamApi {
  FakeXtream({required this.connectResults, this.categoryResult});

  final List<ApiResult<XtreamSession>> connectResults;
  ApiResult<List<XtreamCategory>>? categoryResult;
  int connectCalls = 0;
  final List<XtreamSection> categoryCalls = [];

  @override
  Future<ApiResult<XtreamSession>> connect(XtreamServer server) async {
    final i = connectCalls < connectResults.length
        ? connectCalls
        : connectResults.length - 1;
    connectCalls++;
    return connectResults[i];
  }

  @override
  Future<ApiResult<List<XtreamCategory>>> categories(
    XtreamSession session,
    XtreamSection section,
  ) async {
    categoryCalls.add(section);
    return categoryResult ??
        const ApiSuccess<List<XtreamCategory>>([
          XtreamCategory(id: '1', name: 'Esportes'),
        ]);
  }
}

void main() {
  test('conecta e já carrega as categorias ao vivo', () async {
    final api = FakeXtream(connectResults: [ApiSuccess(_session)]);
    final provider = ServerSessionProvider(api, _server);
    addTearDown(provider.dispose);

    await provider.connect();

    expect(provider.phase, ConnectionPhase.ready);
    expect(provider.session, isNotNull);
    expect(api.categoryCalls, [XtreamSection.live]);
    expect(provider.section(XtreamSection.live).items!.single.name, 'Esportes');
  });

  test('categorias de uma seção são carregadas uma única vez', () async {
    final api = FakeXtream(connectResults: [ApiSuccess(_session)]);
    final provider = ServerSessionProvider(api, _server);
    addTearDown(provider.dispose);
    await provider.connect();

    await provider.loadCategories(XtreamSection.vod);
    await provider.loadCategories(XtreamSection.vod);

    expect(api.categoryCalls.where((s) => s == XtreamSection.vod), hasLength(1));
  });

  test('falha de conexão vira failed e connect() tenta de novo', () async {
    final api = FakeXtream(connectResults: [
      const ApiTimeout<XtreamSession>(),
      ApiSuccess(_session),
    ]);
    final provider = ServerSessionProvider(api, _server);
    addTearDown(provider.dispose);

    await provider.connect();
    expect(provider.phase, ConnectionPhase.failed);
    expect(provider.error, isNotNull);

    await provider.connect();
    expect(provider.phase, ConnectionPhase.ready);
    expect(provider.error, isNull);
  });

  test('credenciais recusadas mostram a mensagem do servidor', () async {
    final api = FakeXtream(connectResults: [
      const ApiError<XtreamSession>('AUTH_FAILED', 'Usuário ou senha recusados pelo servidor.'),
    ]);
    final provider = ServerSessionProvider(api, _server);
    addTearDown(provider.dispose);

    await provider.connect();

    expect(provider.phase, ConnectionPhase.failed);
    expect(provider.error, contains('recusados'));
  });

  test('erro ao listar categorias fica só na seção e permite forçar', () async {
    final api = FakeXtream(
      connectResults: [ApiSuccess(_session)],
      categoryResult: const ApiTimeout<List<XtreamCategory>>(),
    );
    final provider = ServerSessionProvider(api, _server);
    addTearDown(provider.dispose);
    await provider.connect();

    expect(provider.phase, ConnectionPhase.ready);
    expect(provider.section(XtreamSection.live).error, isNotNull);

    api.categoryResult = null;
    await provider.loadCategories(XtreamSection.live, force: true);

    expect(provider.section(XtreamSection.live).items, isNotNull);
    expect(provider.section(XtreamSection.live).error, isNull);
  });
}
