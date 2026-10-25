/// Minúsculas e sem acento, para comparar textos na busca ("Ação" == "acao").
String normalizeForSearch(String input) {
  final lower = input.toLowerCase();
  // Caminho rápido: só ASCII (a maioria dos nomes) não precisa de troca de letras.
  var ascii = true;
  for (final u in lower.codeUnits) {
    if (u > 127) {
      ascii = false;
      break;
    }
  }
  if (ascii) return lower.trim();

  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().trim();
}
