import 'package:barclayflix/app.dart';
import 'package:barclayflix/core/network/api_result.dart';
import 'package:barclayflix/features/auth/data/auth_repository.dart';
import 'package:barclayflix/features/auth/data/device_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedChecker implements DeviceChecker {
  _FixedChecker(this.result);

  final ApiResult<DeviceCheck> result;

  @override
  Future<ApiResult<DeviceCheck>> checkDevice() async => result;
}

void main() {
  testWidgets('dispositivo novo mostra o código de ativação', (tester) async {
    await tester.pumpWidget(BarclayFlixApp(
      checker: _FixedChecker(const ApiSuccess(DeviceCheck(
        status: DeviceStatus.naoRegistrado,
        activationCode: 'A3F9-21CD',
      ))),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('A3F9-21CD'), findsOneWidget);
    expect(find.text('Aguardando ativação…'), findsOneWidget);

    // Desmonta a árvore para cancelar o timer de polling.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('falha de rede mostra erro e botão de tentar novamente',
      (tester) async {
    await tester.pumpWidget(BarclayFlixApp(
      checker: _FixedChecker(const ApiNetworkError<DeviceCheck>('x')),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Não foi possível conectar'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dispositivo ativo mostra a home placeholder', (tester) async {
    await tester.pumpWidget(BarclayFlixApp(
      checker: _FixedChecker(const ApiSuccess(DeviceCheck(
        status: DeviceStatus.ativo,
        activationCode: 'A3F9-21CD',
        clienteNome: 'Fulano',
      ))),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Dispositivo ativo'), findsOneWidget);
    expect(find.text('Cliente: Fulano'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
