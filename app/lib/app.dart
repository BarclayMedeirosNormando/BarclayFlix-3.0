import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/state/auth_provider.dart';
import 'features/auth/ui/activation_screen.dart';
import 'features/auth/ui/status_screen.dart';
import 'features/favorites/data/favorites_repository.dart';
import 'features/home/ui/home_placeholder_screen.dart';
import 'features/progress/data/progress_repository.dart';
import 'features/version/data/version_repository.dart';
import 'features/version/state/version_provider.dart';
import 'features/xtream/data/xtream_client.dart';

class BarclayFlixApp extends StatelessWidget {
  const BarclayFlixApp({
    super.key,
    required this.checker,
    this.xtream,
    this.progress = const NullProgressApi(),
    this.favorites = const NullFavoritesApi(),
    this.version = const NullVersionApi(),
    this.appVersion = '0.0.0',
  });

  final DeviceChecker checker;

  /// Cliente Xtream. Se omitido, usa o [XtreamClient] real.
  final XtreamApi? xtream;

  /// Progresso de reprodução (padrão: nenhum, usado em testes).
  final ProgressApi progress;

  /// Minha lista (padrão: nenhuma, usado em testes).
  final FavoritesApi favorites;

  /// Checagem de versão (padrão: nenhuma, usado em testes) e versão instalada.
  final VersionApi version;
  final String appVersion;

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
        Provider<FavoritesApi>.value(value: favorites),
        ChangeNotifierProvider(create: (_) => AuthProvider(checker)..start()),
        ChangeNotifierProvider(create: (_) => VersionProvider(version, appVersion)..check()),
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
    final version = context.watch<VersionProvider>();
    if (version.force) {
      return StatusScreen(
        icon: Icons.system_update,
        title: 'Atualização necessária',
        message: 'Esta versão (${version.current}) não é mais aceita. '
            'Instale a versão ${version.info.minSupported.isEmpty ? 'mais nova' : version.info.minSupported}.'
            '${version.info.updateUrl.isEmpty ? '\nFale com o administrador.' : '\nBaixe em: ${version.info.updateUrl}'}',
        actionLabel: 'Verificar de novo',
        onAction: version.check,
      );
    }
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

/// Escala responsiva: a interface é desenhada para ~1600x900 (densa, estilo TV). Em telas largas
/// (TV, Windows) que tenham menos espaço lógico que isso, reduz tudo na mesma
/// proporção; nunca amplia. Celular (<900 px de largura) usa o layout compacto.
class _TvScale extends StatelessWidget {
  const _TvScale({required this.child});

  final Widget child;

  static const double refWidth = 1600;
  static const double refHeight = 900;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    if (size.width < 900) return child;
    final scale = (size.width / refWidth < size.height / refHeight
            ? size.width / refWidth
            : size.height / refHeight)
        .clamp(0.5, 1.0);
    if (scale >= 0.99) return child;
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
