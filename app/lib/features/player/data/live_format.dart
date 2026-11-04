/// Formato (extensão) de um canal ao vivo Xtream: `ts` ou `m3u8`.
///
/// Usado pela reconexão do player para trocar de formato quando o atual cai.
/// A URL leva usuário e senha: nada aqui registra a URL.
String urlExtension(Uri url) {
  final path = url.path;
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot < slash) return '';
  return path.substring(dot + 1).toLowerCase();
}

/// Mesma URL com outra extensão no último trecho do caminho (`/live/u/p/1.ts` → `.m3u8`).
Uri withUrlExtension(Uri url, String ext) {
  final path = url.path;
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot < slash) return url;
  return url.replace(path: '${path.substring(0, dot)}.$ext');
}

/// O outro formato: `ts` ↔ `m3u8`.
String otherLiveFormat(String ext) => ext == 'm3u8' ? 'ts' : 'm3u8';

/// Código HTTP citado numa mensagem de erro do player (`h404`), ou vazio.
/// Só o número é aproveitado: a mensagem pode conter a URL com usuário e senha.
String httpCodeTag(String message) {
  final m = RegExp(r'(?:HTTP error|returned) (\d{3})').firstMatch(message);
  return m == null ? '' : ' h${m.group(1)}';
}
