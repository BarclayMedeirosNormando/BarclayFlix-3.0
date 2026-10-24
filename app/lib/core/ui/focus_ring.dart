import 'package:flutter/material.dart';

/// Botões com anel branco quando focados (D-Pad e teclado).
ButtonStyle focusRingStyle() => ButtonStyle(
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? const BorderSide(color: Colors.white, width: 3)
            : null,
      ),
    );

/// Rola até o item focado para ele não ficar escondido ao navegar com as setas.
void ensureVisibleOnFocus(BuildContext context) {
  Scrollable.maybeOf(context)?.position.ensureVisible(
        context.findRenderObject()!,
        alignment: 0.5,
        duration: const Duration(milliseconds: 120),
      );
}
