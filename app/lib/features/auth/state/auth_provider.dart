import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_result.dart';
import '../data/auth_repository.dart';
import '../data/device_models.dart';

enum AuthPhase { loading, awaitingActivation, active, blocked, expired, failed }

/// Estado de ativação do dispositivo.
///
/// - Enquanto o dispositivo está `nao_registrado`, consulta a API a cada
///   [pollInterval] até ser liberado.
/// - Falha de rede no primeiro contato vira [AuthPhase.failed] (com retry);
///   falha durante a espera da ativação só gera um aviso, sem trocar de tela.
///
/// TODO(sessão): guardar a última resposta `ativo` em cache local para abrir
/// o app mesmo offline e revalidar em segundo plano.
class AuthProvider extends ChangeNotifier {
  AuthProvider(
    this._checker, {
    this.pollInterval = const Duration(seconds: 6),
  });

  final DeviceChecker _checker;
  final Duration pollInterval;

  AuthPhase _phase = AuthPhase.loading;
  DeviceCheck? _device;
  ApiResult<DeviceCheck>? _lastFailure;

  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  AuthPhase get phase => _phase;
  DeviceCheck? get device => _device;

  /// Mensagem da última falha de rede/API, ou `null` se a última chamada deu certo.
  String? get failureMessage => _lastFailure?.failureMessage;

  Future<void> start() => _refresh();

  /// "Tentar novamente" / "Já renovei": volta ao carregamento e consulta de novo.
  Future<void> retry() {
    _phase = AuthPhase.loading;
    _lastFailure = null;
    _notify();
    return _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final result = await _checker.checkDevice();
      if (_disposed) return;
      switch (result) {
        case ApiSuccess<DeviceCheck>(:final data):
          _apply(data);
        default:
          _applyFailure(result);
      }
    } finally {
      _busy = false;
    }
  }

  void _apply(DeviceCheck data) {
    _device = data;
    _lastFailure = null;
    _phase = switch (data.status) {
      DeviceStatus.ativo => AuthPhase.active,
      DeviceStatus.naoRegistrado => AuthPhase.awaitingActivation,
      DeviceStatus.bloqueado => AuthPhase.blocked,
      DeviceStatus.expirado => AuthPhase.expired,
    };
    if (_phase == AuthPhase.awaitingActivation) {
      _timer ??= Timer.periodic(pollInterval, (_) => _refresh());
    } else {
      _stopPolling();
    }
    _notify();
  }

  void _applyFailure(ApiResult<DeviceCheck> failure) {
    _lastFailure = failure;
    if (_phase != AuthPhase.awaitingActivation) {
      _phase = AuthPhase.failed;
      _stopPolling();
    }
    _notify();
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    super.dispose();
  }
}
