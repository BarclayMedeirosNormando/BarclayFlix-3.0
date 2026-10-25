import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/settings/video_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../version/state/version_provider.dart';

/// Conteúdo das configurações (usado na aba "Ajustes" e na tela avulsa).
class SettingsView extends StatelessWidget {
  const SettingsView({super.key, this.serverName, this.onChangeServer});

  /// Servidor atual (quando aberto dentro de um servidor).
  final String? serverName;

  /// Mostra o botão "Trocar de servidor" quando informado.
  final VoidCallback? onChangeServer;

  @override
  Widget build(BuildContext context) {
    final version = context.watch<VersionProvider>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        const _SectionTitle('VÍDEO'),
        ValueListenableBuilder<bool>(
          valueListenable: VideoSettings.compat,
          builder: (context, on, _) => _Card(
            child: SwitchListTile(
              autofocus: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Modo compatibilidade de vídeo',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text(
                'Ligue se o vídeo travar ou engasgar. Usa mais processamento do aparelho.',
              ),
              value: on,
              onChanged: VideoSettings.setCompat,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<bool>(
          valueListenable: VideoSettings.lite,
          builder: (context, on, _) => _Card(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Modo leve',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text(
                'Menos efeitos visuais e menos memória. Ajuda TVs e aparelhos antigos. '
                'Reabra o vídeo para valer no player.',
              ),
              value: on,
              onChanged: VideoSettings.setLite,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const _SectionTitle('APLICATIVO'),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Line('Versão instalada', version.current),
              if (version.info.latest.isNotEmpty) _Line('Versão mais nova', version.info.latest),
              if (serverName != null) _Line('Servidor', serverName!),
              const SizedBox(height: 8),
              if (version.updateAvailable)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Há uma versão nova disponível.'
                    '${version.info.updateUrl.isEmpty ? ' Fale com o administrador.' : '\nBaixe em: ${version.info.updateUrl}'}',
                    style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
                  ),
                )
              else if (version.checkedOnce)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Você está na versão mais recente.',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: version.checking ? null : version.check,
                    icon: version.checking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.system_update),
                    label: const Text('Verificar atualização'),
                  ),
                  if (onChangeServer != null)
                    OutlinedButton.icon(
                      onPressed: onChangeServer,
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Trocar de servidor'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tela avulsa (aberta na escolha de servidor).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 24, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Voltar',
                    icon: const Icon(Icons.arrow_back),
                    style: ButtonStyle(
                      side: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.focused)
                            ? const BorderSide(color: Colors.white, width: 2)
                            : null,
                      ),
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 8),
                  const Text('Configurações',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const Expanded(child: SettingsView()),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.5,
            color: AppColors.textMuted,
          ),
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 2),
        ),
        child: child,
      );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.textMuted))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
