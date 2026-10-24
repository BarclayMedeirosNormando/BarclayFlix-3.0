import 'package:flutter/foundation.dart';
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
        builder: (context, child) => _TvScale(child: child ?? const SizedBox()),
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

/// Em TVs Android a tela lógica é pequena e a interface (desenhada para 1080p)
/// fica grande demais; reduz tudo proporcionalmente. Celular e Windows: sem efeito.
class _TvScale extends StatelessWidget {
  const _TvScale({required this.child});

  final Widget child;

  static const double scale = 0.75;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final isTv = defaultTargetPlatform == TargetPlatform.android &&
        size.width >= 900 &&
        size.width / size.height > 1.6;
    if (!isTv) return child;
    final inner = Size(size.width / scale, size.height / scale);
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: inner.width,
        maxWidth: inner.width,
        minHeight: inner.height,
        maxHeight: inner.height,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.topLeft,
          child: MediaQuery(
            data: mq.copyWith(size: inner),
            child: SizedBox(width: inner.width, height: inner.height, child: child),
          ),
        ),
      ),
    );
  }
}
