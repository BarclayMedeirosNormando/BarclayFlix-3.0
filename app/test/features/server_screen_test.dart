import 'package:barclayflix/core/network/api_result.dart';
import 'package:barclayflix/features/auth/data/device_models.dart';
import 'package:barclayflix/features/xtream/data/xtream_client.dart';
import 'package:barclayflix/features/xtream/data/xtream_models.dart';
import 'package:barclayflix/features/xtream/state/server_session_provider.dart';
import 'package:barclayflix/features/xtream/ui/server_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/unused_xtream.dart';

const _server = XtreamServer(
  id: 's1',
  apelido: 'TVPLAY',
  hosts: ['http://a.xyz'],
  username: 'u',
  password: 'p',
);

class _Api with UnusedXtreamMethods implements XtreamApi {
  _Api(this.connectResult);

  final ApiResult<XtreamSession> connectResult;

  @override
  Future<ApiResult<XtreamSession>> connect(XtreamServer server) async => connectResult;

  @override
  Future<ApiResult<List<XtreamCategory>>> categories(
    XtreamSession session,
    XtreamSection section,
  ) async =>
      const ApiSuccess<List<XtreamCategory>>([
        XtreamCategory(id: '1', name: 'Canais de Esportes'),
      ]);

  @override
  Future<ApiResult<List<XtreamChannel>>> liveStreams(
    XtreamSession session,
    String categoryId,
  ) async =>
      const ApiSuccess<List<XtreamChannel>>([
        XtreamChannel(id: '10', name: 'Canal Teste'),
      ]);
}

Widget _app(XtreamApi api) => MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => ServerSessionProvider(api, _server)..connect(),
        child: const ServerScreen(),
      ),
    );

void main() {
  testWidgets('mostra dados da conta, abas e categorias ao vivo', (tester) async {
    final session = XtreamSession(
      server: _server,
      baseUri: Uri.parse('http://a.xyz'),
      userInfo: XtreamUserInfo(
        authorized: true,
        status: 'Active',
        expiresAt: DateTime(2026, 12, 15),
        maxConnections: 2,
        activeConnections: 1,
        isTrial: false,
      ),
    );

    await tester.pumpWidget(_app(_Api(ApiSuccess(session))));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Vence em 15/12/2026'), findsOneWidget);
    expect(find.textContaining('Conexões: 1/2'), findsOneWidget);
    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Ao vivo'), findsOneWidget);
    expect(find.text('Filmes'), findsOneWidget);
    expect(find.text('Séries'), findsOneWidget);

    // O Início é a aba padrão; as categorias aparecem em "Ao vivo".
    await tester.tap(find.text('Ao vivo'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Canais de Esportes'), findsOneWidget);
  });

  testWidgets('credenciais recusadas mostram erro e botão de tentar novamente',
      (tester) async {
    await tester.pumpWidget(_app(_Api(
      const ApiError<XtreamSession>('AUTH_FAILED', 'Usuário ou senha recusados pelo servidor.'),
    )));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('recusados'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });
}
