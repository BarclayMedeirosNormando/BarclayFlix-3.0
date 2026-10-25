import 'package:barclayflix/core/network/api_result.dart';
import 'package:barclayflix/features/version/data/version_repository.dart';
import 'package:barclayflix/features/version/state/version_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api implements VersionApi {
  _Api(this.result);

  final ApiResult<VersionInfo> result;

  @override
  Future<ApiResult<VersionInfo>> check() async => result;
}

void main() {
  test('compareVersions compara número a número', () {
    expect(compareVersions('3.0.0', '3.0.0'), 0);
    expect(compareVersions('3.0.0', '3.0.1'), lessThan(0));
    expect(compareVersions('3.10.0', '3.9.9'), greaterThan(0));
    expect(compareVersions('3.0', '3.0.0'), 0);
    expect(compareVersions('3.0.0+5', '3.0.0'), 0);
  });

  test('force bloqueia; latest maior avisa sem bloquear', () async {
    final p = VersionProvider(
      _Api(const ApiSuccess(VersionInfo(
        latest: '3.1.0',
        minSupported: '3.0.0',
        force: false,
        updateUrl: '',
      ))),
      '3.0.0',
    );
    await p.check();
    expect(p.force, isFalse);
    expect(p.updateAvailable, isTrue);

    final old = VersionProvider(
      _Api(const ApiSuccess(VersionInfo(
        latest: '3.1.0',
        minSupported: '3.0.0',
        force: true,
        updateUrl: 'https://x.test/app.apk',
      ))),
      '2.9.0',
    );
    await old.check();
    expect(old.force, isTrue);
  });

  test('falha de rede nunca bloqueia o app', () async {
    final p = VersionProvider(_Api(ApiTimeout<VersionInfo>()), '1.0.0');
    await p.check();
    expect(p.force, isFalse);
    expect(p.updateAvailable, isFalse);
    expect(p.checkedOnce, isTrue);
  });

  test('VersionInfo.fromJson lê a resposta da API', () {
    final i = VersionInfo.fromJson({
      'latest': '3.0.0',
      'min_supported': '3.0.0',
      'force': true,
      'update_url': ' https://x.test ',
    });
    expect(i.force, isTrue);
    expect(i.updateUrl, 'https://x.test');
  });
}
