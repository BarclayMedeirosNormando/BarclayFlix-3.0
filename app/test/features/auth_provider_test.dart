import 'package:barclayflix/core/network/api_result.dart';
import 'package:barclayflix/features/auth/data/auth_repository.dart';
import 'package:barclayflix/features/auth/data/device_models.dart';
import 'package:barclayflix/features/auth/state/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeChecker implements DeviceChecker {
  FakeChecker(this.results);

  final List<ApiResult<DeviceCheck>> results;
  int calls = 0;

  @override
  Future<ApiResult<DeviceCheck>> checkDevice() async {
    final i = calls < results.length ? calls : results.length - 1;
    calls++;
    return results[i];
  }
}

ApiResult<DeviceCheck> ok(DeviceStatus s) =>
    ApiSuccess(DeviceCheck(status: s, activationCode: 'A3F9-21CD'));

const Duration fast = Duration(milliseconds: 10);

void main() {
  test('aguarda ativação, consulta de novo e para quando fica ativo', () async {
    final checker = FakeChecker([
      ok(DeviceStatus.naoRegistrado),
      ok(DeviceStatus.naoRegistrado),
      ok(DeviceStatus.ativo),
    ]);
    final auth = AuthProvider(checker, pollInterval: fast);
    addTearDown(auth.dispose);

    await auth.start();
    expect(auth.phase, AuthPhase.awaitingActivation);
    expect(auth.device?.activationCode, 'A3F9-21CD');

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(auth.phase, AuthPhase.active);

    final callsWhenActive = checker.calls;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(checker.calls, callsWhenActive, reason: 'polling deve parar');
  });

  test('falha no primeiro contato vira failed e retry recupera', () async {
    final checker = FakeChecker([
      const ApiNetworkError<DeviceCheck>('sem rede'),
      ok(DeviceStatus.naoRegistrado),
    ]);
    final auth = AuthProvider(checker, pollInterval: const Duration(minutes: 5));
    addTearDown(auth.dispose);

    await auth.start();
    expect(auth.phase, AuthPhase.failed);
    expect(auth.failureMessage, isNotNull);

    await auth.retry();
    expect(auth.phase, AuthPhase.awaitingActivation);
    expect(auth.failureMessage, isNull);
  });

  test('falha durante a espera mantém a tela e só avisa', () async {
    final checker = FakeChecker([
      ok(DeviceStatus.naoRegistrado),
      const ApiTimeout<DeviceCheck>(),
    ]);
    final auth = AuthProvider(checker, pollInterval: fast);
    addTearDown(auth.dispose);

    await auth.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(auth.phase, AuthPhase.awaitingActivation);
    expect(auth.failureMessage, isNotNull);
  });

  test('bloqueado e expirado mapeiam para a fase certa', () async {
    final blocked = AuthProvider(FakeChecker([ok(DeviceStatus.bloqueado)]));
    final expired = AuthProvider(FakeChecker([ok(DeviceStatus.expirado)]));
    addTearDown(blocked.dispose);
    addTearDown(expired.dispose);

    await blocked.start();
    await expired.start();

    expect(blocked.phase, AuthPhase.blocked);
    expect(expired.phase, AuthPhase.expired);
  });
}
