enum PlayKind { live, vod, episode }

/// Algo que o player sabe tocar: canal, filme ou episódio.
class PlayItem {
  const PlayItem({
    required this.title,
    required this.url,
    required this.kind,
    this.progressId,
    this.imageUrl,
    this.epgId,
    this.startAt = Duration.zero,
  });

  final String title;

  /// Leva usuário e senha: nunca registrar em log.
  final Uri url;
  final PlayKind kind;

  /// Chave do progresso (filme: id; episódio: `serie:episodio`). Nulo em canais.
  final String? progressId;
  final String? imageUrl;

  /// Id do canal para buscar a programação (só canais ao vivo).
  final String? epgId;

  /// Onde retomar (zero = do início).
  final Duration startAt;

  bool get isLive => kind == PlayKind.live;

  PlayItem withStart(Duration start) => PlayItem(
        title: title,
        url: url,
        kind: kind,
        progressId: progressId,
        imageUrl: imageUrl,
        epgId: epgId,
        startAt: start,
      );
}
