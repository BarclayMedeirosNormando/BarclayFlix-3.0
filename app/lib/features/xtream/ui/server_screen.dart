import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../data/xtream_models.dart';
import '../state/server_session_provider.dart';
import 'live_view.dart';

/// Tela provisória de um servidor: dados reais da conta e categorias por seção.
/// O design definitivo (grades, carrosséis) vem dos mockups.
class ServerScreen extends StatelessWidget {
  const ServerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerSessionProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(provider.server.apelido)),
      body: switch (provider.phase) {
        ConnectionPhase.connecting => const _Connecting(),
        ConnectionPhase.failed => _ConnectionFailure(
            message: provider.error ?? 'Erro desconhecido.',
            onRetry: provider.connect,
          ),
        ConnectionPhase.ready => _ReadyBody(session: provider.session!),
      },
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

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({required this.session});

  final XtreamSession session;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ServerSessionProvider>();
    return DefaultTabController(
      length: XtreamSection.values.length,
      child: Column(
        children: [
          _AccountInfo(info: session.userInfo),
          TabBar(
            tabs: [for (final s in XtreamSection.values) Tab(text: s.label)],
            onTap: (i) => provider.loadCategories(XtreamSection.values[i]),
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final s in XtreamSection.values) _CategoryList(section: s),
              ],
            ),
          ),
        ],
      ),
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
  const _CategoryList({required this.section});

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
