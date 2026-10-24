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
    return _stream('live', channel.id, ext);
  }

  /// Filme (VOD) pelo id e extensão do contêiner (`mp4`, `mkv`...).
  Uri movieUrl(String id, String extension) => _stream('movie', id, extension);

  /// Episódio de série pelo id do episódio e extensão do contêiner.
  Uri episodeUrl(String id, String extension) => _stream('series', id, extension);

  Uri _stream(String kind, String id, String ext) => baseUri.replace(
        path: '${baseUri.path}/$kind/${Uri.encodeComponent(server.username)}'
            '/${Uri.encodeComponent(server.password)}/$id.$ext',
      );
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


/// Filme (`get_vod_streams`).
class XtreamMovie {
  const XtreamMovie({
    required this.id,
    required this.name,
    required this.extension,
    this.posterUrl,
    this.rating,
  });

  factory XtreamMovie.fromJson(JsonMap j) => XtreamMovie(
        id: '${j['stream_id']}',
        name: '${j['name'] ?? ''}',
        extension: _asExtension(j['container_extension']),
        posterUrl: _asUrl(j['stream_icon']),
        rating: _asRating(j['rating']),
      );

  final String id;
  final String name;
  final String extension;
  final String? posterUrl;
  final String? rating;
}

/// Série (`get_series`).
class XtreamSeries {
  const XtreamSeries({
    required this.id,
    required this.name,
    this.coverUrl,
    this.plot,
    this.rating,
    this.year,
  });

  factory XtreamSeries.fromJson(JsonMap j) => XtreamSeries(
        id: '${j['series_id']}',
        name: '${j['name'] ?? ''}',
        coverUrl: _asUrl(j['cover']),
        plot: _asText(j['plot']),
        rating: _asRating(j['rating']),
        year: _asYear(j['releaseDate'] ?? j['release_date']),
      );

  final String id;
  final String name;
  final String? coverUrl;
  final String? plot;
  final String? rating;
  final String? year;
}

/// Episódio de uma série (`get_series_info`).
class XtreamEpisode {
  const XtreamEpisode({
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    required this.extension,
    this.duration,
    this.thumbUrl,
  });

  factory XtreamEpisode.fromJson(JsonMap j, int season) {
    final info = j['info'] is Map<String, dynamic>
        ? j['info'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final secs = int.tryParse('${info['duration_secs'] ?? ''}');
    return XtreamEpisode(
      id: '${j['id']}',
      season: int.tryParse('${j['season'] ?? ''}') ?? season,
      number: int.tryParse('${j['episode_num'] ?? ''}') ?? 0,
      title: _asText(j['title']) ?? 'Episódio',
      extension: _asExtension(j['container_extension']),
      duration: secs == null || secs <= 0 ? null : Duration(seconds: secs),
      thumbUrl: _asUrl(info['movie_image']),
    );
  }

  final String id;
  final int season;
  final int number;
  final String title;
  final String extension;
  final Duration? duration;
  final String? thumbUrl;
}

/// Detalhe de uma série: dados gerais e episódios por temporada.
class XtreamSeriesDetail {
  const XtreamSeriesDetail({
    required this.name,
    required this.seasons,
    this.coverUrl,
    this.plot,
    this.rating,
    this.year,
  });

  factory XtreamSeriesDetail.fromJson(JsonMap j) {
    final info = j['info'] is Map<String, dynamic>
        ? j['info'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final seasons = <int, List<XtreamEpisode>>{};

    void addAll(int season, Object? list) {
      if (list is! List<dynamic>) return;
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          final ep = XtreamEpisode.fromJson(e, season);
          seasons.putIfAbsent(ep.season, () => []).add(ep);
        }
      }
    }

    final raw = j['episodes'];
    if (raw is Map<String, dynamic>) {
      raw.forEach((key, value) => addAll(int.tryParse(key) ?? 1, value));
    } else if (raw is List<dynamic>) {
      for (final (i, value) in raw.indexed) {
        addAll(i + 1, value);
      }
    }
    for (final list in seasons.values) {
      list.sort((a, b) => a.number.compareTo(b.number));
    }
    return XtreamSeriesDetail(
      name: _asText(info['name']) ?? '',
      coverUrl: _asUrl(info['cover']),
      plot: _asText(info['plot']),
      rating: _asRating(info['rating']),
      year: _asYear(info['releaseDate'] ?? info['release_date']),
      seasons: Map.fromEntries(
        seasons.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    );
  }

  final String name;
  final String? coverUrl;
  final String? plot;
  final String? rating;
  final String? year;

  /// Temporadas em ordem crescente.
  final Map<int, List<XtreamEpisode>> seasons;

  XtreamEpisode? episodeById(String id) {
    for (final list in seasons.values) {
      for (final e in list) {
        if (e.id == id) return e;
      }
    }
    return null;
  }
}

/// Dados de um filme (`get_vod_info`), usados para retomar a reprodução.
class XtreamVodInfo {
  const XtreamVodInfo({
    required this.id,
    required this.name,
    required this.extension,
    this.imageUrl,
  });

  factory XtreamVodInfo.fromJson(JsonMap j, String fallbackId) {
    final info = j['info'] is Map<String, dynamic>
        ? j['info'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final data = j['movie_data'] is Map<String, dynamic>
        ? j['movie_data'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return XtreamVodInfo(
      id: '${data['stream_id'] ?? fallbackId}',
      name: _asText(info['name']) ?? _asText(data['name']) ?? 'Filme',
      extension: _asExtension(data['container_extension']),
      imageUrl: _asUrl(info['movie_image']),
    );
  }

  final String id;
  final String name;
  final String extension;
  final String? imageUrl;
}

String _asExtension(Object? v) {
  final s = '${v ?? ''}'.trim().replaceAll('.', '');
  return s.isEmpty ? 'mp4' : s;
}

String? _asText(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty ? null : s;
}

/// Nota com uma casa decimal; `null` se vazia ou zero.
String? _asRating(Object? v) {
  final d = double.tryParse('${v ?? ''}'.replaceAll(',', '.'));
  if (d == null || d <= 0) return null;
  return d.toStringAsFixed(1);
}

String? _asYear(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.length >= 4 && int.tryParse(s.substring(0, 4)) != null
      ? s.substring(0, 4)
      : null;
}
