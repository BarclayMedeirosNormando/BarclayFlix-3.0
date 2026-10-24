import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_provider.dart';

/// Tela de ativação: mostra o código do dispositivo e aguarda a liberação.
/// Também cobre o carregamento inicial e a falha com "Tentar novamente".
class ActivationScreen extends StatelessWidget {
  const ActivationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: switch (auth.phase) {
                AuthPhase.failed => _Failure(
                    message: auth.failureMessage ?? 'Erro desconhecido.',
                    onRetry: auth.retry,
                  ),
                AuthPhase.awaitingActivation => _Waiting(
                    code: auth.device?.activationCode ?? '----',
                    warning: auth.failureMessage,
                  ),
                _ => const _Loading(),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Conectando…'),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.code, this.warning});

  final String code;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.tv, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('Ative este dispositivo', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Text(
            code,
            style: theme.textTheme.displaySmall?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 4,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Informe este código ao administrador para liberar o acesso.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Aguardando ativação…'),
          ],
        ),
        if (warning != null) ...[
          const SizedBox(height: 16),
          Text(
            '$warning Tentando novamente…',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text('Não foi possível conectar', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        // autofocus: o D-Pad já começa nesse botão.
        FilledButton(
          autofocus: true,
          onPressed: onRetry,
          child: const Text('Tentar novamente'),
        ),
      ],
    );
  }
}
