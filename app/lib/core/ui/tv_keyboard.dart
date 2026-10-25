import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Teclado na tela para a TV: letras, números, espaço, apagar e limpar.
///
/// O teclado do sistema não aparece de forma confiável quando o foco chega ao campo
/// pelo controle remoto (D-Pad). Este teclado é do próprio app: cada tecla recebe
/// foco com as setas e OK digita.
class TvKeyboard extends StatelessWidget {
  const TvKeyboard({
    super.key,
    required this.onChar,
    required this.onBackspace,
    required this.onClear,
    this.autofocus = true,
  });

  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  /// A primeira tecla (A) já nasce com o foco.
  final bool autofocus;

  static const List<String> rows = ['ABCDEF', 'GHIJKL', 'MNOPQR', 'STUVWX', 'YZ0123', '456789'];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++)
          Row(
            children: [
              for (var i = 0; i < rows[r].length; i++)
                Expanded(
                  child: _Key(
                    label: rows[r][i],
                    autofocus: autofocus && r == 0 && i == 0,
                    onTap: () => onChar(rows[r][i]),
                  ),
                ),
            ],
          ),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _Key(label: 'Espaço', icon: Icons.space_bar, onTap: () => onChar(' ')),
            ),
            Expanded(
              flex: 2,
              child: _Key(label: 'Apagar', icon: Icons.backspace_outlined, onTap: onBackspace),
            ),
            Expanded(
              flex: 2,
              child: _Key(label: 'Limpar', icon: Icons.clear, onTap: onClear),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({required this.label, required this.onTap, this.icon, this.autofocus = false});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(3),
      child: InkWell(
        autofocus: widget.autofocus,
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => _focused = f),
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _focused ? const Color(0xFF1B1F28) : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? Colors.white : AppColors.border,
              width: _focused ? 3 : 2,
            ),
          ),
          child: widget.icon == null
              ? Text(widget.label,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 22),
                    const SizedBox(width: 6),
                    Text(widget.label,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
        ),
      ),
    );
  }
}
