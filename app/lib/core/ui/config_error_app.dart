import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Exibida quando a configuração de build é inválida (ex.: API_URL vazia).
/// Evita o erro silencioso do 2.0, em que F5 sem `--dart-define` só aparecia
/// como falha genérica de ativação.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.problem});

  final String problem;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.settings_suggest, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      'Configuração inválida',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(problem, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    const Text(
                      'Rode o app com scripts\\run_dev.ps1 (ou F5 no VS Code), '
                      'que passam app/config.local.json.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
