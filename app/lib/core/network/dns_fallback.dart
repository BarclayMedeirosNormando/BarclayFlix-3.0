import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Destino de reprodução: a URL (possivelmente com o IP no lugar do nome) e os
/// cabeçalhos extras que o player precisa enviar.
class PlaybackTarget {
  const PlaybackTarget(this.url, [this.headers]);

  final Uri url;
  final Map<String, String>? headers;
}

/// Alguns provedores de internet bloqueiam o DNS de certos servidores de IPTV (o nome
/// não resolve, ou aponta para 0.0.0.0), e o servidor só abre depois de trocar o DNS do
/// aparelho para 8.8.8.8 ou 1.1.1.1. Este resolvedor faz isso dentro do app:
///
/// 1. Pergunta ao DNS do sistema. Se resolver, nada muda (devolve nulo).
/// 2. Se falhar ou devolver endereço de bloqueio, pergunta ao Cloudflare e ao Google
///    por DNS sobre HTTPS (pelos IPs 1.1.1.1 e 8.8.8.8, que não dependem de DNS).
///
/// A resposta fica em memória por alguns minutos. Só os nomes dos servidores do usuário
/// são consultados, e só quando o DNS da rede falha.
class DnsFallback {
  DnsFallback({Future<InternetAddress?> Function(String host)? resolver})
      : _resolver = resolver;

  static final DnsFallback instance = DnsFallback();

  static const List<String> _providers = [
    'https://1.1.1.1/dns-query',
    'https://8.8.8.8/resolve',
  ];

  final Future<InternetAddress?> Function(String host)? _resolver;
  final Map<String, _Entry> _cache = {};

  /// IP que deve ser usado no lugar de [host], ou nulo quando o DNS do sistema serve.
  Future<InternetAddress?> overrideFor(String host) async {
    if (InternetAddress.tryParse(host) != null) return null;
    final now = DateTime.now();
    final cached = _cache[host];
    if (cached != null && cached.expires.isAfter(now)) return cached.address;

    final found = await (_resolver ?? _resolve)(host);
    _cache[host] = _Entry(
      found,
      now.add(found == null ? const Duration(minutes: 2) : const Duration(minutes: 5)),
    );
    return found;
  }

  /// Para o player (mpv), que resolve nomes por conta própria: troca o nome pelo IP e
  /// manda o nome no cabeçalho `Host`. Só para http; em https o nome é necessário ao
  /// certificado, então a URL fica como está.
  Future<PlaybackTarget> forPlayback(Uri url) async {
    if (url.scheme != 'http') return PlaybackTarget(url);
    final ip = await overrideFor(url.host);
    if (ip == null) return PlaybackTarget(url);
    final host = url.hasPort ? '${url.host}:${url.port}' : url.host;
    return PlaybackTarget(url.replace(host: ip.address), {'Host': host});
  }

  /// Endereço que um provedor usa para bloquear (ou resposta que não leva a lugar nenhum).
  static bool isSinkhole(InternetAddress a) =>
      a.isLoopback || a.isMulticast || a.address == '0.0.0.0' || a.address == '::';

  /// Primeiro endereço IPv4 válido de uma resposta DNS em JSON (formato do Cloudflare e
  /// do Google), ou nulo.
  static InternetAddress? parseAnswer(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
    final answers = json is Map ? json['Answer'] : null;
    if (answers is! List) return null;
    for (final a in answers) {
      if (a is Map && a['type'] == 1) {
        final ip = InternetAddress.tryParse('${a['data']}');
        if (ip != null && ip.type == InternetAddressType.IPv4 && !isSinkhole(ip)) return ip;
      }
    }
    return null;
  }

  Future<InternetAddress?> _resolve(String host) async {
    try {
      final system =
          await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
      if (system.any((a) => !isSinkhole(a))) return null;
    } on Exception {
      // Falhou ou demorou: segue para o DNS sobre HTTPS.
    }
    for (final base in _providers) {
      final ip = await _doh(base, host).timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      if (ip != null) return ip;
    }
    return null;
  }

  Future<InternetAddress?> _doh(String base, String host) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final uri = Uri.parse(base).replace(queryParameters: {'name': host, 'type': 'A'});
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final response = await request.close();
      if (response.statusCode != 200) return null;
      return parseAnswer(await response.transform(utf8.decoder).join());
    } on Exception {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

class _Entry {
  const _Entry(this.address, this.expires);

  final InternetAddress? address;
  final DateTime expires;
}

/// Hosts (servidores de IPTV do usuário) cujo certificado HTTPS pode ser aceito mesmo
/// vencido, autoassinado ou de outro domínio. Qualquer outro host (painel, Apps Script,
/// DNS sobre HTTPS) segue com a verificação normal.
class TlsTrust {
  TlsTrust._();

  static final Set<String> _hosts = {};

  static void allow(String host) => _hosts.add(host.toLowerCase());

  static bool accepts(String host) => _hosts.contains(host.toLowerCase());
}

/// Faz todo `HttpClient` do app (API, imagens, painel) usar o [DnsFallback].
/// Instalar uma vez, em `main()`: `HttpOverrides.global = DnsFallbackOverrides();`
class DnsFallbackOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (Uri url, String? proxyHost, int? proxyPort) async {
      final host = proxyHost ?? url.host;
      final port = proxyPort ?? url.port;
      final ip = await DnsFallback.instance.overrideFor(host);
      final target = ip ?? host;

      if (proxyHost != null || url.scheme != 'https') {
        return Socket.startConnect(target, port);
      }

      // https: o HttpClient NÃO criptografa o socket que a fábrica devolve, então ele já
      // sai criptografado daqui. Com o DNS bloqueado, a conexão vai para o IP: o
      // certificado não confere com o IP, e só é aceito para os servidores liberados
      // em [TlsTrust] (o painel, o Apps Script e o DNS sobre HTTPS seguem estritos).
      return SecureSocket.startConnect(
        target,
        port,
        onBadCertificate: (_) => TlsTrust.accepts(url.host),
      );
    };
    return client;
  }
}
