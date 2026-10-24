import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/format.dart';
import '../data/play_item.dart';

/// Chamado com a posição atual (a cada ~30 s e ao sair) em filmes e episódios.
typedef ProgressCallback = void Function(
  PlayItem item,
  Duration position,
  Duration duration,
);

/// Player (media_kit) para canais ao vivo, filmes e episódios.
///
/// Mantém UM único [Player]: o plano do cliente costuma permitir apenas 1
/// conexão, então trocar de item reabre o stream no mesmo player e, ao sair,
/// o player é descartado para liberar a conexão no servidor.
///
/// Ao vivo: ↑/↓ troca de canal, ← sai. Filmes/episódios: ←/→ voltam/avançam
/// 10 s, PageUp/PageDown trocam de episódio. Em todos: OK/Espaço pausa e
/// Esc/Backspace/Voltar saem. Toque na tela mostra/oculta os controles.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.onProgress,
  });

  final List<PlayItem> items;
  final int initialIndex;
  final ProgressCallback? onProgress;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final FocusNode _focus = FocusNode(debugLabel: 'player');
  late int _index = widget.initialIndex;
  Timer? _saveTimer;
  String? _error;
  bool _buffering = true;
  bool _showInfo = true;

  PlayItem get _item => widget.items[_index];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _player.stream.error.listen((e) {
      if (mounted) setState(() => _error = 'Não foi possível reproduzir este item.');
    });
    _player.stream.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
    });
    _saveTimer = Timer.periodic(const Duration(seconds: 30), (_) => _report());
    _open();
  }

  void _report() {
    if (_item.isLive) return;
    widget.onProgress?.call(_item, _player.state.position, _player.state.duration);
  }

  Future<void> _open() async {
    setState(() {
      _error = null;
      _buffering = true;
      _showInfo = true;
    });
    try {
      final start = _item.startAt;
      await _player.open(
        Media(_item.url.toString(), start: start > Duration.zero ? start : null),
      );
    } catch (_) {
      // Sem detalhes: a URL leva usuário e senha.
      if (mounted) setState(() => _error = 'Não foi possível reproduzir este item.');
    }
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.items.length) return;
    _report();
    _index = next;
    _open();
  }

  void _seek(int seconds) {
    final target = _player.state.position + Duration(seconds: seconds);
    _player.seek(target < Duration.zero ? Duration.zero : target);
    setState(() => _showInfo = true);
  }

  void _exit() => Navigator.of(context).maybePop();

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final live = _item.isLive;

    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      _exit();
    } else if (live && key == LogicalKeyboardKey.arrowLeft) {
      _exit();
    } else if (live &&
        (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp)) {
      _go(1);
    } else if (live &&
        (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.pageDown)) {
      _go(-1);
    } else if (!live && key == LogicalKeyboardKey.arrowLeft) {
      _seek(-10);
    } else if (!live && key == LogicalKeyboardKey.arrowRight) {
      _seek(10);
    } else if (!live && key == LogicalKeyboardKey.pageDown) {
      _go(1);
    } else if (!live && key == LogicalKeyboardKey.pageUp) {
      _go(-1);
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
    _saveTimer?.cancel();
    _report();
    _focus.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
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
                        // Botão "Voltar" sempre com destaque: Esc/Voltar fazem o mesmo.
                        InkWell(
                          borderRadius: BorderRadius.circular(32),
                          onTap: _exit,
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
                            item.title,
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
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _Bottom(player: _player, live: item.isLive, hasNext: widget.items.length > 1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra de progresso (filmes/episódios) e atalhos.
class _Bottom extends StatelessWidget {
  const _Bottom({required this.player, required this.live, required this.hasNext});

  final Player player;
  final bool live;
  final bool hasNext;

  @override
  Widget build(BuildContext context) {
    final hints = live
        ? '↑ ↓ trocar de canal     OK pausar     ← voltar'
        : '← → 10 s     OK pausar${hasNext ? '     PgUp PgDn episódio' : ''}     Esc voltar';
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!live) _ProgressBar(player: player),
          if (!live) const SizedBox(height: 12),
          Text(
            hints,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (context, snap) {
        final pos = snap.data ?? player.state.position;
        final dur = player.state.duration;
        final fraction =
            dur.inMilliseconds > 0 ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
        return Row(
          children: [
            Text(formatDuration(pos), style: const TextStyle(color: Colors.white)),
            const SizedBox(width: 16),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 8,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB224)),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(formatDuration(dur), style: const TextStyle(color: Colors.white70)),
          ],
        );
      },
    );
  }
}
