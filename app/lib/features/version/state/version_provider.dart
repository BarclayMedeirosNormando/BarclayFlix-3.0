import 'package:flutter/foundation.dart';

import '../../../core/network/api_result.dart';
import '../data/version_repository.dart';

/// Versão instalada e o que o servidor diz sobre ela.
///
/// Falha de rede nunca bloqueia o app: só uma resposta explícita do servidor
/// (`force`) impede o uso.
class VersionProvider extends ChangeNotifier {
  VersionProvider(this._api, this.current);

  final VersionApi _api;

  /// Versão instalada (ex.: `3.0.0`).
  final String current;

  VersionInfo _info = VersionInfo.none;
  bool _checking = false;
  bool _checkedOnce = false;
  bool _disposed = false;

  VersionInfo get info => _info;
  bool get checking => _checking;
  bool get checkedOnce => _checkedOnce;

  /// Versão antiga demais: o app deve pedir atualização.
  bool get force => _info.force;

  /// Existe versão mais nova (mesmo que a atual ainda seja aceita).
  bool get updateAvailable =>
      _info.latest.isNotEmpty && compareVersions(current, _info.latest) < 0;

  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    _notify();
    final result = await _api.check();
    if (_disposed) return;
    if (result is ApiSuccess<VersionInfo>) _info = result.data;
    _checking = false;
    _checkedOnce = true;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
