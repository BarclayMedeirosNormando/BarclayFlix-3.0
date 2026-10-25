import 'package:barclayflix/core/ui/tv_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(List<String> typed, {void Function()? onBackspace, void Function()? onClear}) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              child: TvKeyboard(
                onChar: typed.add,
                onBackspace: onBackspace ?? () {},
                onClear: onClear ?? () {},
              ),
            ),
          ),
        ),
      );

  testWidgets('toque nas teclas digita letras, números e espaço', (tester) async {
    final typed = <String>[];
    await tester.pumpWidget(host(typed));
    await tester.tap(find.text('B'));
    await tester.tap(find.text('7'));
    await tester.tap(find.text('Espaço'));
    expect(typed, ['B', '7', ' ']);
  });

  testWidgets('Apagar e Limpar chamam os callbacks', (tester) async {
    var back = 0;
    var clear = 0;
    await tester.pumpWidget(host([], onBackspace: () => back++, onClear: () => clear++));
    await tester.tap(find.text('Apagar'));
    await tester.tap(find.text('Limpar'));
    expect([back, clear], [1, 1]);
  });

  testWidgets('a tecla A nasce com o foco e o controle remoto navega e digita', (tester) async {
    final typed = <String>[];
    await tester.pumpWidget(host(typed));
    await tester.pump();

    // OK na tecla focada (A).
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(typed, ['A']);

    // Seta para a direita vai para B; OK digita.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(typed, ['A', 'B']);

    // Seta para baixo vai para H (linha de baixo, mesma coluna); OK digita.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(typed, ['A', 'B', 'H']);
  });
}
