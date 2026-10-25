import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'platform_kind.dart';

/// Tipo de aparelho, usado para adaptar escala, grades e tamanhos.
enum DeviceClass { phone, tablet, desktop, tv }

/// Classificação do aparelho + fator de escala da interface.
///
/// A interface é desenhada densa (~1600x900, estilo TV). Cada tipo de aparelho
/// recebe um fator para que tudo caiba com tamanho confortável:
/// - celular: ~0,82 (menor, mais conteúdo por tela)
/// - tablet: ~0,92
/// - TV e Windows: encaixa em 1600x900 (nunca amplia; mínimo 0,5)
class DeviceProfile {
  const DeviceProfile(this.kind, this.scale);

  final DeviceClass kind;

  /// Fator aplicado ao layout (1.0 = tamanho de desenho).
  final double scale;

  bool get isPhone => kind == DeviceClass.phone;
  bool get isTablet => kind == DeviceClass.tablet;
  bool get isTv => kind == DeviceClass.tv;
  bool get isDesktop => kind == DeviceClass.desktop;

  /// Telas pequenas (celular): menos margem e itens mais compactos.
  bool get compact => kind == DeviceClass.phone;

  /// Plataforma real do aparelho; definida na inicialização (main).
  static AppPlatform platform = AppPlatform.unsupported;

  static const double refWidth = 1600;
  static const double refHeight = 900;
  static const double phoneScale = 0.82;
  static const double tabletScale = 0.92;

  /// [size] é o tamanho lógico real da janela (antes de qualquer escala).
  static DeviceProfile resolve(Size size, {AppPlatform? platform}) {
    final p = platform ?? DeviceProfile.platform;
    final shortest = size.shortestSide;

    final DeviceClass kind;
    switch (p) {
      case AppPlatform.androidTv:
        kind = DeviceClass.tv;
      case AppPlatform.windows:
        kind = DeviceClass.desktop;
      case AppPlatform.android:
        kind = shortest < 600 ? DeviceClass.phone : DeviceClass.tablet;
      case AppPlatform.unsupported:
        // Sem plataforma conhecida (testes): não altera a escala.
        return const DeviceProfile(DeviceClass.desktop, 1.0);
    }

    final double scale;
    switch (kind) {
      case DeviceClass.phone:
        scale = phoneScale;
      case DeviceClass.tablet:
        scale = tabletScale;
      case DeviceClass.tv:
      case DeviceClass.desktop:
        scale = math.min(size.width / refWidth, size.height / refHeight).clamp(0.5, 1.0);
    }
    return DeviceProfile(kind, scale);
  }

  /// Perfil do contexto (definido por [DeviceScope]); padrão neutro se ausente.
  static DeviceProfile of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeviceScope>()?.profile ??
      const DeviceProfile(DeviceClass.desktop, 1.0);
}

/// Disponibiliza o [DeviceProfile] para a árvore (calculado com o tamanho real).
class DeviceScope extends InheritedWidget {
  const DeviceScope({super.key, required this.profile, required super.child});

  final DeviceProfile profile;

  @override
  bool updateShouldNotify(DeviceScope old) =>
      old.profile.kind != profile.kind || old.profile.scale != profile.scale;
}
