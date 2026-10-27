import 'package:barclayflix/features/xtream/data/xtream_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? base(String h) => XtreamClient.baseUri(h)?.toString();

  test('endereço simples e com esquema', () {
    expect(base('http://granfox.xyz/'), 'http://granfox.xyz');
    expect(base('dns.xyz:8080'), 'http://dns.xyz:8080');
    expect(base('https://cinebox.blog'), 'https://cinebox.blog');
  });

  test('tira o caminho da API quando o link inteiro foi colado', () {
    expect(base('https://cinebox.blog/player_api.php'), 'https://cinebox.blog');
    expect(base('http://x.com:8080/get.php?username=a&password=b&type=m3u'), 'http://x.com:8080');
    expect(base('http://x.com/Player_API.php/'), 'http://x.com');
  });

  test('mantém um subcaminho legítimo', () {
    expect(base('http://x.com/painel'), 'http://x.com/painel');
  });

  test('vazio ou inválido vira nulo', () {
    expect(base('  '), isNull);
  });
}
