import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Item selecionável com foco visível (anel branco) para D-Pad, mouse e toque.
/// Enter/OK ativam [onTap]; [onFocus] avisa quando o item ganha o foco.
class FocusTile extends StatefulWidget {
  const FocusTile({
    super.key,
    required this.child,
    required this.onTap,
    this.onFocus,
    this.onLongPress,
    this.selected = false,
    this.autofocus = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onFocus;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool autofocus;
  final EdgeInsetsGeometry padding;

  @override
  State<FocusTile> createState() => _FocusTileState();
}

class _FocusTileState extends State<FocusTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = _focused
        ? Colors.white
        : widget.selected
            ? AppColors.accent
            : Colors.transparent;
    final background = widget.selected
        ? AppColors.accent.withValues(alpha: 0.14)
        : _focused
            ? const Color(0xFF1B1F28)
            : AppColors.surface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        autofocus: widget.autofocus,
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) {
            widget.onFocus?.call();
            // Mantém o item focado visível ao navegar com as setas.
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 120),
            );
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: _focused ? 3 : 2),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
