import 'package:barclayflix/core/network/api_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('erro de rede mostra o motivo técnico quando existe', () {
    const r = ApiNetworkError<int>('HTTP 403');
    expect(r.failureMessage, contains('Sem conexão com o servidor'));
    expect(r.failureMessage, contains('(HTTP 403)'));
  });

  test('erro de rede sem motivo mantém a mensagem simples', () {
    const r = ApiNetworkError<int>();
    expect(r.failureMessage, 'Sem conexão com o servidor. Verifique a internet.');
  });
}
