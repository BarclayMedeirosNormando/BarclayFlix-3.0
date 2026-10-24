/// Configuração de build. A URL da API NUNCA fica no código versionado:
/// ela vem de `--dart-define-from-file=config.local.json`.
class AppConfig {
  const AppConfig(this.apiUrl);

  factory AppConfig.fromEnvironment() =>
      const AppConfig(String.fromEnvironment('API_URL'));

  final String apiUrl;

  /// `null` se a configuração é válida; caso contrário, o motivo em pt-BR.
  /// O app valida isso ao iniciar e mostra uma tela de erro clara, em vez de
  /// falhar em silêncio com uma URL vazia.
  String? get problem {
    if (apiUrl.trim().isEmpty) {
      return 'A variável API_URL não foi definida neste build.';
    }
    final uri = Uri.tryParse(apiUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'API_URL não é uma URL válida: "$apiUrl".';
    }
    if (uri.scheme != 'https') {
      return 'API_URL precisa usar https (Apps Script só responde em https).';
    }
    return null;
  }
}
