import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/format.dart';
import '../../../core/settings/video_settings.dart';
import '../../xtream/data/xtream_models.dart' show EpgEntry;
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
    this.epgLoader,
  });

  final List<PlayItem> items;
  final int initialIndex;
  final ProgressCallback? onProgress;

  /// Busca a programação de um canal ao vivo (opcional).
  final Future<List<EpgEntry>> Function(String streamId)? epgLoader;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player(
    configuration: PlayerConfiguration(
      // Aparelho fraco (modo leve): buffer menor para não faltar memória.
      bufferSize: (VideoSettings.lite.value ? 32 : 64) * 1024 * 1024,
    ),
  );
  late final VideoController _video = VideoController(
    _player,
    configuration: VideoControllerConfiguration(
      hwdec: VideoSettings.compat.value ? 'no' : 'auto-safe',
      enableHardwareAcceleration: true,
    ),
  );
  final FocusNode _focus = FocusNode(debugLabel: 'player');
  final FocusNode _playFocus = FocusNode(debugLabel: 'play');
  // Botões da barra, na ordem em que aparecem: ←/→ andam de um para o outro
  // sem depender da busca de foco do Flutter (que falhava em algumas TVs).
  final List<FocusNode> _btnNodes = List.generate(12, (i) => FocusNode(debugLabel: 'btn$i'));
  final List<FocusNode> _order = [];
  int _auto = 0;
  BoxFit _fit = BoxFit.contain;
  String? _hint;
  final List<DateTime> _stalls = [];
  bool _boosted = false;
  Timer? _hintTimer;
  late int _index = widget.initialIndex;
  Timer? _saveTimer;
  Timer? _hideTimer;
  Duration? _resumeAt;
  StreamSubscription<bool>? _completedSub;
  Timer? _nextTimer;
  int _nextIn = 0;
  List<EpgEntry> _epg = const [];
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
    _completedSub = _player.stream.completed.listen((done) {
      if (done && mounted) _onCompleted();
    });
    _player.stream.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
      if (b) _onStall();
    });
    _saveTimer = Timer.periodic(const Duration(seconds: 30), (_) => _report());
    _open();
  }

  /// Mostra os controles e os esconde após 4 s sem interação.
  void _poke() {
    if (!mounted) return;
    setState(() => _showInfo = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _error == null) {
        setState(() => _showInfo = false);
        _focus.requestFocus();
      }
    });
  }

  /// Mostra os controles e, se pedido, põe o foco (D-Pad) no botão de pausa.
  void _showControls({bool focusPlay = false}) {
    _poke();
    if (focusPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playFocus.requestFocus();
      });
    }
  }

  void _report() {
    if (_item.isLive) return;
    widget.onProgress?.call(_item, _player.state.position, _player.state.duration);
  }

  /// Ajustes de rede/cache e, no modo compatibilidade, decodificação por software.
  Future<void> _tuneForWeakDevices() async {
    try {
      final native = _player.platform;
      if (native is NativePlayer) {
        await native.setProperty('hwdec', VideoSettings.compat.value ? 'no' : 'auto-safe');
        await native.setProperty('cache', 'yes');
        await native.setProperty('demuxer-readahead-secs', _item.isLive ? '10' : '30');
        await native.setProperty('network-timeout', '15');
      }
    } catch (_) {
      // Ajuste opcional: se falhar, segue com o padrão.
    }
  }

  /// Internet oscilando: se o vídeo parar 3 vezes em 90 s, aumenta o buffer
  /// (mais segundos guardados à frente) para aguentar as quedas.
  void _onStall() {
    // A primeira "parada" é só a abertura do vídeo.
    if (_player.state.position < const Duration(seconds: 5)) return;
    final now = DateTime.now();
    _stalls
      ..add(now)
      ..removeWhere((t) => now.difference(t) > const Duration(seconds: 90));
    if (_boosted || _stalls.length < 3) return;
    _boosted = true;
    final secs = _item.isLive ? 25 : (VideoSettings.lite.value ? 40 : 60);
    try {
      final native = _player.platform;
      if (native is NativePlayer) native.setProperty('demuxer-readahead-secs', '$secs');
    } catch (_) {}
  }

  /// Programação do canal (agora/depois); sem guia, nada aparece.
  Future<void> _loadEpg() async {
    final id = _item.epgId;
    final loader = widget.epgLoader;
    if (!_item.isLive || id == null || loader == null) return;
    try {
      final list = await loader(id);
      if (mounted && _item.epgId == id) setState(() => _epg = list);
    } catch (_) {
      // Sem programação: segue sem ela.
    }
  }

  /// Episódio terminou: se houver próximo, avisa e avança sozinho em 5 s.
  void _onCompleted() {
    if (_item.kind != PlayKind.episode || _index + 1 >= widget.items.length) return;
    _report();
    _nextTimer?.cancel();
    setState(() => _nextIn = 5);
    _nextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_nextIn <= 1) {
        _playNext();
      } else {
        setState(() => _nextIn--);
      }
    });
  }

  void _playNext() {
    _cancelNext();
    _go(1);
  }

  void _cancelNext() {
    _nextTimer?.cancel();
    _nextTimer = null;
    if (_nextIn != 0 && mounted) setState(() => _nextIn = 0);
  }

  Future<void> _open() async {
    _cancelNext();
    _stalls.clear();
    _boosted = false;
    setState(() {
      _error = null;
      _buffering = true;
      _epg = const [];
    });
    _loadEpg();
    _poke();
    try {
      await _tuneForWeakDevices();
      final start = _resumeAt ?? _item.startAt;
      _resumeAt = null;
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

  void _seek(int seconds, {bool fromKey = false}) {
    final dur = _player.state.duration;
    var target = _player.state.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (dur > Duration.zero && target > dur) target = dur;
    _player.seek(target);
    if (!fromKey) return _poke();
    // Pelo controle: só um aviso discreto, sem abrir a barra (assim as setas
    // continuam livres para navegar pelos botões quando a barra estiver aberta).
    setState(() => _hint =
        '${seconds > 0 ? '+' : '−'}${seconds.abs()} s   ·   ${formatDuration(target)} / ${formatDuration(dur)}');
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  void _exit() => Navigator.of(context).maybePop();

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final live = _item.isLive;

    final isArrow = key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    final isOk = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space;

    // Foco nos botões da barra: as setas navegam entre eles e OK aciona o botão.
    if (_showInfo && _nextIn == 0 && !_focus.hasPrimaryFocus && (isArrow || isOk)) {
      _poke();
      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
        final i = _order.indexWhere((n) => n.hasPrimaryFocus);
        if (i >= 0) {
          final j = key == LogicalKeyboardKey.arrowRight ? i + 1 : i - 1;
          if (j >= 0 && j < _order.length) _order[j].requestFocus();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }

    // Aviso do próximo episódio: OK assiste agora; ← ou ↓ cancela.
    if (_nextIn > 0) {
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.space) {
        _playNext();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowDown) {
        _cancelNext();
        return KeyEventResult.handled;
      }
    }

    // O botão Voltar do controle/Android (goBack) é tratado pelo sistema, que já
    // fecha a tela; tratar aqui também fechava duas telas de uma vez.
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace) {
      _exit();
    } else if (live && key == LogicalKeyboardKey.arrowLeft) {
      _exit();
    } else if (live &&
        (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp)) {
      _go(1);
    } else if (live &&
        (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.pageDown)) {
      _go(-1);
    } else if (!live &&
        (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown)) {
      _showControls(focusPlay: true);
    } else if (!live &&
        (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight)) {
      if (_showInfo) {
        // Barra aberta: as setas passam a navegar pelos botões.
        _showControls(focusPlay: true);
      } else {
        _seek(key == LogicalKeyboardKey.arrowRight ? 10 : -10, fromKey: true);
      }
    } else if (!live && key == LogicalKeyboardKey.pageDown) {
      _go(1);
    } else if (!live && key == LogicalKeyboardKey.pageUp) {
      _go(-1);
    } else if (isOk) {
      if (_showInfo) {
        _player.playOrPause();
        _poke();
      } else {
        _showControls(focusPlay: true);
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _saveTimer?.cancel();
    _hideTimer?.cancel();
    _hintTimer?.cancel();
    _nextTimer?.cancel();
    _completedSub?.cancel();
    _report();
    _focus.dispose();
    _playFocus.dispose();
    for (final n in _btnNodes) {
      n.dispose();
    }
    _player.dispose();
    super.dispose();
  }


  static final ButtonStyle _focusRing = ButtonStyle(
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? const BorderSide(color: Colors.white, width: 2)
          : null,
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused) ? Colors.white24 : Colors.transparent,
    ),
  );

  Widget _ctl(IconData icon, String tip, VoidCallback onTap,
      {FocusNode? focus, double size = 30}) {
    final node = focus ?? _btnNodes[_auto++];
    if (focus == null) _order.add(node);
    return IconButton(
      focusNode: node,
      tooltip: tip,
      iconSize: size,
      color: Colors.white,
      style: _focusRing,
      icon: Icon(icon),
      onPressed: () {
        onTap();
        _poke();
      },
    );
  }

  bool _reg(FocusNode n) {
    _order.add(n);
    return false;
  }

  /// Barra inferior no estilo dos players de IPTV: progresso + fileira de botões.
  Widget _bottomBar(PlayItem item) {
    final live = item.isLive;
    final many = widget.items.length > 1;
    _order.clear();
    _auto = 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 12),
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
          if (!live) _ProgressBar(player: _player, onTouch: _poke),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              if (!live) _ctl(Icons.replay_10, 'Voltar 10 s', () => _seek(-10)),
              _ctl(Icons.close, 'Sair', _exit),
              if (many) _ctl(Icons.skip_previous, live ? 'Canal anterior' : 'Anterior', () => _go(-1)),
              if (_reg(_playFocus)) const SizedBox.shrink(),
              StreamBuilder<bool>(
                stream: _player.stream.playing,
                initialData: _player.state.playing,
                builder: (context, snap) => _ctl(
                  snap.data == true ? Icons.pause : Icons.play_arrow,
                  snap.data == true ? 'Pausar' : 'Reproduzir',
                  _player.playOrPause,
                  focus: _playFocus,
                  size: 40,
                ),
              ),
              if (many) _ctl(Icons.skip_next, live ? 'Próximo canal' : 'Próximo', () => _go(1)),
              if (!live) _ctl(Icons.forward_10, 'Avançar 10 s', () => _seek(10)),
              if (many && !live) _ctl(Icons.layers, 'Episódios', _pickEpisode),
              _ctl(Icons.aspect_ratio, 'Tamanho da imagem', _cycleFit),
              _ctl(Icons.audiotrack, 'Áudio', _pickAudio),
              _ctl(Icons.closed_caption, 'Legendas', _pickSubtitle),
              if (!live) _ctl(Icons.settings, 'Velocidade', _pickSpeed),
            ],
          ),
        ],
      ),
    );
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  void _cycleFit() {
    final (next, name) = switch (_fit) {
      BoxFit.contain => (BoxFit.cover, 'Preencher a tela (corta as bordas)'),
      BoxFit.cover => (BoxFit.fill, 'Esticar'),
      _ => (BoxFit.contain, 'Original'),
    };
    setState(() => _fit = next);
    _toast('Imagem: $name');
  }

  /// Lista de opções (TV/controle/toque) usada por episódios, áudio, legenda e velocidade.
  Future<void> _pick(
    String title,
    List<({String label, bool selected, VoidCallback onTap})> options,
  ) async {
    _hideTimer?.cancel();
    final anySelected = options.any((o) => o.selected);
    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (var i = 0; i < options.length; i++)
            ListTile(
              autofocus: options[i].selected || (!anySelected && i == 0),
              leading: Icon(
                  options[i].selected ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(options[i].label),
              onTap: () {
                Navigator.pop(ctx);
                options[i].onTap();
              },
            ),
        ],
      ),
    );
    if (mounted) _showControls(focusPlay: true);
  }

  String _trackName(String id, String? title, String? language, int n) {
    final parts = [
      if (title != null && title.isNotEmpty) title,
      if (language != null && language.isNotEmpty) language,
    ];
    return parts.isEmpty ? 'Faixa $n' : parts.join(' · ');
  }

  void _pickEpisode() => _pick('Episódios', [
        for (var i = 0; i < widget.items.length; i++)
          (
            label: widget.items[i].title,
            selected: i == _index,
            onTap: () {
              if (i == _index) return;
              _report();
              setState(() => _index = i);
              _open();
            },
          ),
      ]);

  void _pickAudio() {
    final tracks =
        _player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    if (tracks.length < 2) return _toast('Este vídeo só tem uma faixa de áudio.');
    final current = _player.state.track.audio.id;
    _pick('Áudio', [
      for (var i = 0; i < tracks.length; i++)
        (
          label: _trackName(tracks[i].id, tracks[i].title, tracks[i].language, i + 1),
          selected: tracks[i].id == current,
          onTap: () => _player.setAudioTrack(tracks[i]),
        ),
    ]);
  }

  void _pickSubtitle() {
    final tracks =
        _player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
    if (tracks.isEmpty) return _toast('Este vídeo não tem legendas.');
    final current = _player.state.track.subtitle.id;
    _pick('Legendas', [
      (
        label: 'Desativadas',
        selected: current == 'no',
        onTap: () => _player.setSubtitleTrack(SubtitleTrack.no()),
      ),
      for (var i = 0; i < tracks.length; i++)
        (
          label: _trackName(tracks[i].id, tracks[i].title, tracks[i].language, i + 1),
          selected: tracks[i].id == current,
          onTap: () => _player.setSubtitleTrack(tracks[i]),
        ),
    ]);
  }

  void _pickSpeed() {
    final rate = _player.state.rate;
    _pick('Velocidade', [
      for (final r in const [0.75, 1.0, 1.25, 1.5, 2.0])
        (
          label: r == 1.0 ? 'Normal' : '${r}x',
          selected: (rate - r).abs() < 0.01,
          onTap: () => _player.setRate(r),
        ),
    ]);
  }

  /// "Agora: X · Depois: Y" a partir da programação do canal.
  String? _epgLine() {
    if (_epg.isEmpty) return null;
    final now = DateTime.now();
    EpgEntry? current;
    EpgEntry? next;
    for (final e in _epg) {
      if (e.isLiveAt(now)) {
        current = e;
      } else if (e.start.isAfter(now) && next == null) {
        next = e;
      }
    }
    if (current == null && next == null) return null;
    String hm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return [
      if (current != null) 'Agora: ${current.title} (até ${hm(current.end)})',
      if (next != null) 'Depois: ${next.title} (${hm(next.start)})',
    ].join('   ·   ');
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
          onTap: () {
            if (_showInfo) {
              _hideTimer?.cancel();
              setState(() => _showInfo = false);
              _focus.requestFocus();
            } else {
              _poke();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: _video, controls: NoVideoControls, fit: _fit),
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
              if (_hint != null && !_showInfo)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 48,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(_hint!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              if (_nextIn > 0)
                Positioned(
                  right: 24,
                  bottom: 110,
                  child: _NextUp(
                    seconds: _nextIn,
                    title: widget.items[_index + 1].title,
                    onPlay: _playNext,
                    onCancel: _cancelNext,
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
                        IconButton(
                          tooltip: 'Voltar',
                          color: Colors.white,
                          icon: const Icon(Icons.arrow_back),
                          style: _focusRing,
                          onPressed: _exit,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                              ),
                              if (item.isLive && _epgLine() != null)
                                Text(
                                  _epgLine()!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_showInfo)
                Positioned(left: 0, right: 0, bottom: 0, child: _bottomBar(item)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.player, required this.onTouch});

  final Player player;
  final VoidCallback onTouch;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (context, snap) {
        final pos = snap.data ?? player.state.position;
        final dur = player.state.duration;
        final max = dur.inMilliseconds.toDouble();
        final value = max > 0 ? pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble() : 0.0;
        return Row(
          children: [
            Text(formatDuration(pos), style: const TextStyle(color: Colors.white)),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFFFFB224),
                  inactiveTrackColor: Colors.white24,
                  thumbColor: const Color(0xFFFFB224),
                  trackHeight: 5,
                ),
                child: Slider(
                  value: value,
                  max: max > 0 ? max : 1,
                  onChanged: max > 0
                      ? (v) {
                          player.seek(Duration(milliseconds: v.round()));
                          onTouch();
                        }
                      : null,
                ),
              ),
            ),
            Text(formatDuration(dur), style: const TextStyle(color: Colors.white70)),
          ],
        );
      },
    );
  }
}

/// Aviso "Próximo episódio em N s" com botões (toque) e atalhos (OK/←).
class _NextUp extends StatelessWidget {
  const _NextUp({
    required this.seconds,
    required this.title,
    required this.onPlay,
    required this.onCancel,
  });

  final int seconds;
  final String title;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Próximo episódio em $seconds s',
              style: const TextStyle(
                  color: Color(0xFFFFB224), fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  autofocus: true,
                  onPressed: onPlay,
                  child: const Text('Assistir agora'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: onCancel, child: const Text('Cancelar')),
            ],
          ),
          const SizedBox(height: 4),
          const Text('OK assiste agora · ← cancela',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}
