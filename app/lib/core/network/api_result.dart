/// Objeto JSON decodificado.
typedef JsonMap = Map<String, dynamic>;

/// Resultado tipado de uma chamada à API.
///
/// Cada tipo de falha é distinto, para a interface reagir de forma diferente
/// a cada um (nada de `code: null` genérico).
sealed class ApiResult<T> {
  const ApiResult();

  /// Dados em caso de sucesso, `null` caso contrário.
  T? get dataOrNull => switch (this) {
        ApiSuccess<T>(:final data) => data,
        _ => null,
      };

  /// Mensagem amigável (pt-BR) em caso de falha, `null` em caso de sucesso.
  String? get failureMessage => switch (this) {
        ApiSuccess<T>() => null,
        ApiError<T>(:final code, :final message) => _apiErrorMessage(code, message),
        ApiNetworkError<T>() => 'Sem conexão com o servidor. Verifique a internet.',
        ApiTimeout<T>() => 'O servidor demorou para responder.',
        ApiBadPayload<T>() => 'Resposta inesperada do servidor.',
      };
}

/// Chamada concluída com `ok: true`.
final class ApiSuccess<T> extends ApiResult<T> {
  const ApiSuccess(this.data);
  final T data;
}

/// O servidor respondeu `ok: false` com um código de erro.
final class ApiError<T> extends ApiResult<T> {
  const ApiError(this.code, this.message);
  final String code;
  final String message;
}

/// Sem rede, DNS, conexão recusada ou HTTP diferente de 200.
final class ApiNetworkError<T> extends ApiResult<T> {
  const ApiNetworkError([this.message = '']);
  final String message;
}

/// A chamada excedeu o tempo limite.
final class ApiTimeout<T> extends ApiResult<T> {
  const ApiTimeout();
}

/// Corpo que não é JSON, não segue o envelope ou tem campos inesperados.
final class ApiBadPayload<T> extends ApiResult<T> {
  const ApiBadPayload([this.message = '']);
  final String message;
}

String _apiErrorMessage(String code, String message) {
  switch (code) {
    case 'SCHEMA_ERROR':
      return 'Erro de configuração no servidor (planilha). Avise o administrador.';
    case 'UPGRADE_REQUIRED':
      return 'Atualize o aplicativo para continuar.';
    case 'BUSY':
      return 'Servidor ocupado. Tente novamente em instantes.';
    case 'BAD_REQUEST':
      return 'Requisição inválida${message.isEmpty ? '' : ': $message'}';
    default:
      return message.isEmpty ? 'Erro no servidor ($code).' : message;
  }
}
