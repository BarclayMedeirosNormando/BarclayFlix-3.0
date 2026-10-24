import 'package:barclayflix/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('API_URL vazia é problema', () {
    expect(const AppConfig('').problem, isNotNull);
    expect(const AppConfig('   ').problem, isNotNull);
  });

  test('URL sem host ou inválida é problema', () {
    expect(const AppConfig('abc').problem, isNotNull);
    expect(const AppConfig('https://').problem, isNotNull);
  });

  test('http (sem TLS) é problema', () {
    expect(const AppConfig('http://script.google.com/macros/s/X/exec').problem,
        isNotNull);
  });

  test('https válido não tem problema', () {
    expect(const AppConfig('https://script.google.com/macros/s/X/exec').problem,
        isNull);
  });
}
