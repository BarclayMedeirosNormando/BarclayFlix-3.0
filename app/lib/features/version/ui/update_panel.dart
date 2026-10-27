import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/focus_ring.dart';
import '../data/app_updater.dart';

/// Botão "Atualizar agora" com progresso do download, funciona com D-Pad.
///
/// [url] é o `update_url` do servidor; pode conter `{abi}`.
class UpdatePanel extends StatefulWidget {
  const UpdatePanel({super.key, required this.url, this.autofocus = false, this.updater});

  final String url;
  final bool autofocus;

  /// Para testes.
  final AppUpdater? updater;

  @override
  State<UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<UpdatePanel> {
  late final AppUpdater _updater = widget.updater ?? AppUpdater();

  @override
  void dispose() {
    if (widget.updater == null) _updater.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _updater,
      builder: (context, _) {
        final u = _updater;
        if (u.phase == UpdatePhase.downloading || u.phase == UpdatePhase.installing) {
          final percent = u.progress == null ? null : (u.progress! * 100).floor();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                u.phase == UpdatePhase.installing
                    ? 'Abrindo o instalador… toque em "Instalar".'
                    : 'Baixando atualização${percent == null ? '…' : ' $percent%'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: u.phase == UpdatePhase.installing ? null : u.progress),
              if (u.phase == UpdatePhase.downloading) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  autofocus: true,
                  style: focusRingStyle(),
                  onPressed: u.cancel,
                  child: const Text('Cancelar'),
                ),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (u.phase == UpdatePhase.error && u.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(u.error!, style: const TextStyle(color: AppColors.accent)),
              ),
            FilledButton.icon(
              autofocus: widget.autofocus,
              style: focusRingStyle(),
              onPressed: () => u.start(widget.url),
              icon: const Icon(Icons.system_update),
              label: Text(u.phase == UpdatePhase.error ? 'Tentar de novo' : 'Atualizar agora'),
            ),
          ],
        );
      },
    );
  }
}
