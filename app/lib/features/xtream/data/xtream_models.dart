import '../../../core/network/api_result.dart';
import '../../auth/data/device_models.dart';

/// Seções do catálogo Xtream.
enum XtreamSection {
  live('get_live_categories', 'Ao vivo'),
  vod('get_vod_categories', 'Filmes'),
  series('get_series_categories', 'Séries');

  const XtreamSection(this.action, this.label);

  /// Valor do parâmetro `action` em `player_api.php`.
  final String action;
  final String label;
}

/// Dados da conta devolvidos por `player_api.php` (campo `user_info`).
/// Os painéis misturam número, texto e booleano; por isso o parsing é tolerante.
class XtreamUserInfo {
  const XtreamUserInfo({
    required this.authorized,
    required this.status,
    required this.expiresAt,
    required this.maxConnections,
    required this.activeConnections,
    required this.isTrial,
  });

  factory XtreamUserInfo.fromJson(JsonMap j) => XtreamUserInfo(
        authorized: _asBool(j['auth']),
        status: '${j['status'] ?? ''}',
        expiresAt: _asUnixDate(j['exp_date']),
        maxConnections: _asInt(j['max_connections']),
        activeConnections: _asInt(j['active_cons']),
        isTrial: _asBool(j['is_trial']),
      );

  final bool authorized;

  /// Texto do painel (ex.: `Active`, `Expired`, `Disabled`).
  final String status;

  /// `null` quando o plano não vence.
  final DateTime? expiresAt;
  final int maxConnections;
  final int activeConnections;
  final bool isTrial;

  bool get isActive => status.toLowerCase() == 'active';
}

/// Sessão aberta em um servidor: o host que respondeu e a conta autenticada.
class XtreamSession {
  const XtreamSession({
    required this.server,
    required this.baseUri,
    required this.userInfo,
  });

  final XtreamServer server;

  /// Host que respondeu (já normalizado, sem barra final).
  final Uri baseUri;
  final XtreamUserInfo userInfo;

  /// URL de reprodução de um canal ao vivo (leva usuário e senha: nunca logar).
  Uri liveUrl(XtreamChannel channel) {
    final ext = server.streamFormat == StreamFormat.m3u8 ? 'm3u8' : 'ts';
    return baseUri.replace(
      path: '${baseUri.path}/live/${Uri.encodeComponent(server.username)}'
          '/${Uri.encodeComponent(server.password)}/${channel.id}.$ext',
    );
  }
}

/// Canal ao vivo (`get_live_streams`).
class XtreamChannel {
  const XtreamChannel({
    required this.id,
    required this.name,
    this.number,
    this.iconUrl,
  });

  factory XtreamChannel.fromJson(JsonMap j) => XtreamChannel(
        id: '${j['stream_id']}',
        name: '${j['name'] ?? ''}',
        number: int.tryParse('${j['num'] ?? ''}'),
        iconUrl: _asUrl(j['stream_icon']),
      );

  final String id;
  final String name;
  final int? number;
  final String? iconUrl;
}

String? _asUrl(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.startsWith('http') ? s : null;
}

class XtreamCategory {
  const XtreamCategory({required this.id, required this.name});

  factory XtreamCategory.fromJson(JsonMap j) => XtreamCategory(
        id: '${j['category_id']}',
        name: '${j['category_name'] ?? ''}',
      );

  final String id;
  final String name;
}

int _asInt(Object? v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;

bool _asBool(Object? v) => v == true || v == 1 || v == '1';

DateTime? _asUnixDate(Object? v) {
  final seconds = int.tryParse('${v ?? ''}');
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}
