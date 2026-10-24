import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/state/auth_provider.dart';
import 'features/auth/ui/activation_screen.dart';
import 'features/auth/ui/status_screen.dart';
import 'features/home/ui/home_placeholder_screen.dart';
import 'features/progress/data/progress_repository.dart';
import 'features/xtream/data/xtream_client.dart';

class BarclayFlixApp extends StatelessWidget {
  const BarclayFlixApp({
    super.key,
    required this.checker,
    this.xtream,
    this.progress = const NullProgressApi(),
  });

  final DeviceChecker checker;

  /// Cliente Xtream. Se omitido, usa o [XtreamClient] real.
  final XtreamApi? xtream;

  /// Progresso de reprodução (padrão: nenhum, usado em testes).
  final ProgressApi progress;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<XtreamApi>(
          create: (_) => xtream ?? XtreamClient(),
          dispose: (_, api) {
            if (api is XtreamClient) api.dispose();
          },
        ),
        Provider<ProgressApi>.value(value: progress),
        ChangeNotifierProvider(create: (_) => AuthProvider(checker)..start()),
      ],
      child: MaterialApp(
        title: 'BarclayFlix',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const AuthGate(),
      ),
    );
  }
}

/// Escolhe a tela conforme o estado do dispositivo.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return switch (auth.phase) {
      AuthPhase.active => const HomePlaceholderScreen(),
      AuthPhase.blocked => const StatusScreen(
          icon: Icons.block,
          title: 'Acesso bloqueado',
          message: 'Fale com o administrador.',
        ),
      AuthPhase.expired => StatusScreen(
          icon: Icons.event_busy,
          title: 'Assinatura vencida',
          message: 'Renove com o administrador e toque em "Já renovei".',
          actionLabel: 'Já renovei',
          onAction: auth.retry,
        ),
      _ => const ActivationScreen(),
    };
  }
}
