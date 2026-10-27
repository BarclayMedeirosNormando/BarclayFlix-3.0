import 'package:flutter/material.dart';

/// Tela simples de estado (bloqueado, vencido) com ação opcional.
class StatusScreen extends StatelessWidget {
  const StatusScreen({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.extra,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Conteúdo extra abaixo da mensagem (ex.: botão de atualizar).
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                  if (extra != null) ...[const SizedBox(height: 20), extra!],
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 24),
                    FilledButton(
                      autofocus: extra == null,
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
