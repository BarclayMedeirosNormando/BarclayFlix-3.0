import 'package:barclayflix/core/device/device_profile.dart';
import 'package:barclayflix/core/device/platform_kind.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DeviceProfile resolve(double w, double h, AppPlatform p) =>
      DeviceProfile.resolve(Size(w, h), platform: p);

  test('celular Android vira phone com escala compacta', () {
    final p = resolve(411, 890, AppPlatform.android);
    expect(p.kind, DeviceClass.phone);
    expect(p.scale, DeviceProfile.phoneScale);
    // Em paisagem continua celular (lado menor < 600).
    expect(resolve(890, 411, AppPlatform.android).kind, DeviceClass.phone);
  });

  test('tablet Android (lado menor >= 600)', () {
    final p = resolve(800, 1280, AppPlatform.android);
    expect(p.kind, DeviceClass.tablet);
    expect(p.scale, DeviceProfile.tabletScale);
  });

  test('Android TV encaixa em 1600x900 sem ampliar', () {
    final p = resolve(960, 540, AppPlatform.androidTv);
    expect(p.kind, DeviceClass.tv);
    expect(p.scale, closeTo(0.6, 0.001));
    expect(resolve(1920, 1080, AppPlatform.androidTv).scale, 1.0);
  });

  test('Windows: janela grande não amplia, pequena reduz até 0,5', () {
    expect(resolve(1920, 1080, AppPlatform.windows).scale, 1.0);
    expect(resolve(1280, 720, AppPlatform.windows).scale, closeTo(0.8, 0.001));
    expect(resolve(400, 300, AppPlatform.windows).scale, 0.5);
    expect(resolve(1280, 720, AppPlatform.windows).kind, DeviceClass.desktop);
  });

  test('plataforma desconhecida (testes) não altera escala', () {
    expect(resolve(800, 600, AppPlatform.unsupported).scale, 1.0);
  });
}
