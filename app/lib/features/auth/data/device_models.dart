import '../../../core/network/api_result.dart';

/// Estado do dispositivo conforme `check_device`.
enum DeviceStatus {
  ativo('ativo'),
  naoRegistrado('nao_registrado'),
  bloqueado('bloqueado'),
  expirado('expirado');

  const DeviceStatus(this.wire);
  final String wire;

  static DeviceStatus parse(String value) => values.firstWhere(
        (s) => s.wire == value,
        orElse: () => throw FormatException('status desconhecido: $value'),
      );
}

enum StreamFormat { ts, m3u8 }

/// Um servidor Xtream liberado para o dispositivo.
class XtreamServer {
  const XtreamServer({
    required this.id,
    required this.apelido,
    required this.hosts,
    required this.username,
    required this.password,
    this.streamFormat = StreamFormat.ts,
  });

  factory XtreamServer.fromJson(JsonMap j) => XtreamServer(
        id: j['id'] as String,
        apelido: j['apelido'] as String,
        hosts: (j['hosts'] as List<dynamic>).cast<String>(),
        username: j['username'] as String,
        password: j['password'] as String,
        streamFormat:
            j['stream_format'] == 'm3u8' ? StreamFormat.m3u8 : StreamFormat.ts,
      );

  final String id;
  final String apelido;

  /// DNS em ordem de preferência (o primeiro que responder é usado).
  final List<String> hosts;
  final String username;
  final String password;
  final StreamFormat streamFormat;
}

/// Resposta de `check_device`.
class DeviceCheck {
  const DeviceCheck({
    required this.status,
    required this.activationCode,
    this.expiraEm,
    this.clienteNome,
    this.servers = const [],
  });

  factory DeviceCheck.fromJson(JsonMap j) => DeviceCheck(
        status: DeviceStatus.parse(j['status'] as String),
        activationCode: j['activation_code'] as String,
        expiraEm: _parseDate(j['expira_em']),
        clienteNome: (j['cliente'] as Map<String, dynamic>?)?['nome'] as String?,
        servers: ((j['servidores'] as List<dynamic>?) ?? const [])
            .map((e) => XtreamServer.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final DeviceStatus status;

  /// Código exibido na tela de ativação (ex.: `A3F9-21CD`).
  final String activationCode;
  final DateTime? expiraEm;
  final String? clienteNome;
  final List<XtreamServer> servers;

  static DateTime? _parseDate(Object? v) => v is String ? DateTime.tryParse(v) : null;
}
