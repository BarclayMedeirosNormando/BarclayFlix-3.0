import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../xtream/data/xtream_models.dart';

/// Player de canais ao vivo (media_kit).
///
/// Mantém UM único [Player]: o plano do cliente costuma permitir apenas 1
/// conexão, então trocar de canal reabre o stream no mesmo player e, ao sair,
/// o player é descartado para liberar a conexão no servidor.
///
/// Controles: ↑/PageUp = próximo canal, ↓/PageDown = anterior, OK/Espaço =
/// pausar, ← / Esc / Backspace / Voltar = sair. Toque na tela mostra/oculta o título.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.channels,
    required this.initialIndex,
    required this.session,
  });

  final List<XtreamChannel> channels;
  final int initialIndex;
  final XtreamSession session;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final FocusNode _focus = FocusNode(debugLabel: 'player');
  late int _index = widget.initialIndex;
  String? _error;
  bool _buffering = true;
  bool _showInfo = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _player.stream.error.listen((e) {
      if (mounted) setState(() => _error = 'Não foi possível reproduzir este canal.');
    });
    _player.stream.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
    });
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _error = null;
      _buffering = true;
      _showInfo = true;
    });
    try {
      final url = widget.session.liveUrl(widget.channels[_index]);
      await _player.open(Media(url.toString()));
    } catch (_) {
      // Sem detalhes: a URL leva usuário e senha.
      if (mounted) setState(() => _error = 'Não foi possível reproduzir este canal.');
    }
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.channels.length) return;
    _index = next;
    _open();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp) {
      _go(1);
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown) {
      _go(-1);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).maybePop();
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      _player.playOrPause();
      setState(() => _showInfo = true);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _focus.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channels[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showInfo = !_showInfo),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: _video, controls: NoVideoControls),
              if (_buffering && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (_error != null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _open,
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              if (_showInfo)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      children: [
                        // Botão "Voltar" sempre com destaque: a tecla ← (ou Esc)
                        // faz a mesma coisa, e o rótulo deixa isso claro.
                        InkWell(
                          borderRadius: BorderRadius.circular(32),
                          onTap: () => Navigator.of(context).maybePop(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_back, color: Colors.white),
                                SizedBox(width: 8),
                                Text('Voltar',
                                    style: TextStyle(
                                        color: Colors.white, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_showInfo)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _Hints(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Atalhos do player (teclado e controle remoto).
class _Hints extends StatelessWidget {
  const _Hints();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: const Text(
        '↑ ↓ trocar de canal     OK pausar     ← voltar',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white70, fontSize: 16),
      ),
    );
  }
}
