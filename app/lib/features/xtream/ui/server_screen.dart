import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../data/xtream_models.dart';
import '../state/server_session_provider.dart';
import 'live_view.dart';

/// Tela de um servidor: cabeçalho com navegação (Ao vivo, Filmes, Séries),
/// dados reais da conta e a lista da seção escolhida.
class ServerScreen extends StatelessWidget {
  const ServerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerSessionProvider>();
    return Scaffold(
      body: SafeArea(
        child: switch (provider.phase) {
          ConnectionPhase.connecting => const _WithHeader(child: _Connecting()),
          ConnectionPhase.failed => _WithHeader(
              child: _ConnectionFailure(
                message: provider.error ?? 'Erro desconhecido.',
                onRetry: provider.connect,
              ),
            ),
          ConnectionPhase.ready => _ReadyBody(session: provider.session!),
        },
      ),
    );
  }
}

/// Cabeçalho comum: voltar, marca, navegação opcional e nome do servidor.
class _Header extends StatelessWidget {
  const _Header({this.selected, this.onSelect});

  final int? selected;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final server = context.read<ServerSessionProvider>().server;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 24, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back),
            // Anel branco quando focado, como nos demais itens (D-Pad/teclado).
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
          const _Brand(),
          const SizedBox(width: 32),
          if (onSelect != null)
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (i, section) in XtreamSection.values.indexed)
                      _NavItem(
                        label: section.label,
                        selected: i == selected,
                        onTap: () => onSelect!(i),
                      ),
                  ],
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(server.apelido,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Marca "BarclayFlix" (o "Flix" em âmbar).
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3),
        children: [
          TextSpan(text: 'Barclay'),
          TextSpan(text: 'Flix', style: TextStyle(color: AppColors.accent)),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => _focused = f),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: widget.selected ? AppColors.accent : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: widget.selected ? Colors.white : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WithHeader extends StatelessWidget {
  const _WithHeader({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Header(),
        Expanded(child: child),
      ],
    );
  }
}

class _Connecting extends StatelessWidget {
  const _Connecting();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Conectando ao servidor…'),
        ],
      ),
    );
  }
}

class _ConnectionFailure extends StatelessWidget {
  const _ConnectionFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              autofocus: true,
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyBody extends StatefulWidget {
  const _ReadyBody({required this.session});

  final XtreamSession session;

  @override
  State<_ReadyBody> createState() => _ReadyBodyState();
}

class _ReadyBodyState extends State<_ReadyBody> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Header(
          selected: _index,
          onSelect: (i) {
            setState(() => _index = i);
            context.read<ServerSessionProvider>().loadCategories(XtreamSection.values[i]);
          },
        ),
        _AccountInfo(info: widget.session.userInfo),
        Expanded(
          child: _CategoryList(
            key: ValueKey(XtreamSection.values[_index]),
            section: XtreamSection.values[_index],
          ),
        ),
      ],
    );
  }
}

class _AccountInfo extends StatelessWidget {
  const _AccountInfo({required this.info});

  final XtreamUserInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expires = info.expiresAt;
    final parts = <String>[
      info.isActive ? 'Ativo' : info.status,
      expires == null ? 'Sem vencimento' : 'Vence em ${formatDate(expires)}',
      'Conexões: ${info.activeConnections}/${info.maxConnections}',
      if (info.isTrial) 'Teste',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          parts.join('   •   '),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: info.isActive ? null : theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}

class _CategoryList extends StatefulWidget {
  const _CategoryList({super.key, required this.section});

  final XtreamSection section;

  @override
  State<_CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends State<_CategoryList> {
  @override
  void initState() {
    super.initState();
    // Também cobre o deslizar entre abas (o toque já carrega em onTap).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ServerSessionProvider>().loadCategories(widget.section);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerSessionProvider>();
    final state = provider.section(widget.section);

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => provider.loadCategories(widget.section, force: true),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    final items = state.items;
    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return const Center(child: Text('Nenhuma categoria.'));
    }

    if (widget.section == XtreamSection.live) {
      return LiveView(categories: items);
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => ListTile(
        dense: true,
        title: Text(items[i].name),
        // Filmes e séries ainda sem lista; o onTap vazio mantém o item focável
        // (rolagem pelo D-Pad).
        onTap: () {},
      ),
    );
  }
}
