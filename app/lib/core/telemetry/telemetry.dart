import 'dart:async';
import 'dart:convert';

import '../device/device_identity.dart';
import '../network/api_client.dart';
import '../network/api_result.dart';

String _cut(String s, int max) => s.length <= max ? s : s.substring(0, max);

/// Um fato curto sobre uma reprodução, enviado ao painel (monitor).
///
/// Nomes: `start` (começou a abrir), `ok` (abriu), `fail` (não abriu),
/// `drop` (caiu durante a reprodução), `stall` (travando), `hb` (pulso),
/// `stop` (fim). Nunca leva usuário, senha ou endereço do servidor.
class TelemetryEvent {
  TelemetryEvent({
    required this.session,
    required this.serverId,
    required this.name,
    required this.type,
    this.itemId = '',
    this.title = '',
    this.v1 = 0,
    this.v2 = 0,
    this.detail = '',
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String session;
  final String serverId;
  final String name;

  /// `live`, `vod` ou `episode`.
  final String type;
  final String itemId;
  final String title;
  final int v1;
  final int v2;
  final String detail;
  final DateTime at;

  /// Formato compacto da API: a idade do evento é calculada no envio.
  List<Object> toWire(DateTime now) => [
        now.difference(at).inMilliseconds.clamp(0, 6 * 3600 * 1000),
        _cut(session, 16),
        _cut(serverId, 20),
        name,
        type,
        _cut(itemId, 40),
        _cut(title, 50),
        v1,
        v2,
        _cut(detail, 40),
      ];
}

/// Contrato usado pelo player (facilita testes e versões sem backend).
abstract interface class TelemetryApi {
  /// Guarda o evento (nunca lança, nunca espera a rede).
  void log(TelemetryEvent event);

  /// Tenta enviar o que está guardado.
  Future<void> flush();
}

/// Não registra nada (testes e padrão).
class NullTelemetry implements TelemetryApi {
  const NullTelemetry();

  @override
  void log(TelemetryEvent event) {}

  @override
  Future<void> flush() async {}
}

/// Junta eventos e os envia em lotes pequenos para a ação `log_event`.
///
/// - Falha de rede/tempo/ocupado: mantém os eventos e tenta no próximo ciclo.
/// - Recusa da API (ex.: backend antigo, aparelho não ativo): descarta o lote.
/// - Guarda no máximo [maxBuffer] eventos (descarta os mais antigos).
class TelemetryService implements TelemetryApi {
  TelemetryService(
    this._api,
    this._identity, {
    this.flushEvery = const Duration(seconds: 45),
    this.batchSize = 5,
    this.maxBuffer = 300,
  });

  final ApiClient _api;
  final DeviceIdentity _identity;
  final Duration flushEvery;
  final int batchSize;
  final int maxBuffer;

  final List<TelemetryEvent> _queue = [];
  Timer? _timer;
  bool _sending = false;

  int get pending => _queue.length;

  @override
  void log(TelemetryEvent event) {
    try {
      _queue.add(event);
      if (_queue.length > maxBuffer) _queue.removeRange(0, _queue.length - maxBuffer);
      _timer ??= Timer.periodic(flushEvery, (_) => flush());
    } catch (_) {
      // Telemetria nunca pode atrapalhar o vídeo.
    }
  }

  @override
  Future<void> flush() async {
    if (_sending) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty) {
        final batch = _queue.take(batchSize).toList();
        final deviceId = await _identity.getOrCreate();
        final now = DateTime.now();
        final result = await _api.call<bool>(
          'log_event',
          {
            'device_id': deviceId,
            'e': jsonEncode([for (final e in batch) e.toWire(now)]),
          },
          (_) => true,
        );
        final keep = result is ApiNetworkError<bool> ||
            result is ApiTimeout<bool> ||
            (result is ApiError<bool> && result.code == 'BUSY');
        if (keep) break; // tenta de novo no próximo ciclo
        batch.forEach(_queue.remove);
      }
    } catch (_) {
      // Sem detalhes: segue sem telemetria.
    } finally {
      _sending = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
