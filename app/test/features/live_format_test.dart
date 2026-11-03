import 'package:barclayflix/features/player/data/live_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ts = Uri.parse('http://painel.exemplo:8080/live/user/pass/327390.ts');

  test('lê a extensão do último trecho', () {
    expect(urlExtension(ts), 'ts');
    expect(urlExtension(Uri.parse('http://h.exemplo/live/u/p/9.M3U8')), 'm3u8');
    expect(urlExtension(Uri.parse('http://h.exemplo:8080/live/u/p/9')), '');
  });

  test('troca a extensão sem mexer no resto da URL', () {
    final r = withUrlExtension(ts, 'm3u8');
    expect(r.toString(), 'http://painel.exemplo:8080/live/user/pass/327390.m3u8');
    expect(withUrlExtension(r, 'ts'), ts);
  });

  test('não confunde ponto do host ou da senha com extensão', () {
    final u = Uri.parse('http://a.b.exemplo:8080/live/u.1/p.2/55');
    expect(urlExtension(u), '');
    expect(withUrlExtension(u, 'ts'), u);
  });

  test('preserva caracteres codificados no usuário e na senha', () {
    final u = Uri.parse('http://h.exemplo/live/a%40b/c%2Bd/7.ts');
    expect(withUrlExtension(u, 'm3u8').toString(), 'http://h.exemplo/live/a%40b/c%2Bd/7.m3u8');
  });

  test('otherLiveFormat alterna', () {
    expect(otherLiveFormat('ts'), 'm3u8');
    expect(otherLiveFormat('m3u8'), 'ts');
  });

  test('httpCodeTag pega só o número', () {
    expect(httpCodeTag('Failed to open http://h/live/u/p/1.ts: HTTP error 404 Not Found'), ' h404');
    expect(httpCodeTag('Server returned 403 Forbidden'), ' h403');
    expect(httpCodeTag('Connection reset by peer'), '');
  });
}
