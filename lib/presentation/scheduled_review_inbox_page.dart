// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';

import '../application/mana_review_scheduler.dart';

class ScheduledReviewInboxPage extends StatefulWidget {
  const ScheduledReviewInboxPage({super.key, required this.client});
  final ManaReviewSchedulerClient client;

  @override
  State<ScheduledReviewInboxPage> createState() =>
      _ScheduledReviewInboxPageState();
}

class _ScheduledReviewInboxPageState extends State<ScheduledReviewInboxPage> {
  late Future<_ReviewHome> _home;
  ManaReviewRun? _selected;
  Object? _detailError;
  bool _detailLoading = false;

  @override
  void initState() {
    super.initState();
    _home = _load();
  }

  Future<_ReviewHome> _load() async =>
      _ReviewHome(await widget.client.status(), await widget.client.inbox());

  void _reload() => setState(() {
    _home = _load();
    _selected = null;
    _detailError = null;
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<_ReviewHome>(
    future: _home,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError)
        return _empty(
          'PR Inbox unavailable',
          '${snapshot.error}',
          retry: _reload,
        );
      final home = snapshot.requireData;
      if (!home.status.configured) {
        return _empty(
          'PR Inbox is not configured',
          'The host-owned scheduler is disabled by default. Configure it explicitly through Mana before using this viewer.',
        );
      }
      return Row(
        children: [
          SizedBox(width: 390, child: _list(home)),
          const VerticalDivider(width: 1),
          Expanded(child: _detail(home.status)),
        ],
      );
    },
  );

  Widget _list(_ReviewHome home) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'PR Inbox',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh local inbox',
          ),
        ],
      ),
      Text(
        '${home.status.enabled ? 'Enabled' : 'Disabled'} • ${home.status.policy ?? 'no policy'} • credentials stored: ${home.status.credentialsStored}',
      ),
      const SizedBox(height: 16),
      if (home.inbox.items.isEmpty)
        const Text('No requested-review work is stored locally.')
      else
        ...home.inbox.items.map(
          (run) => Card(
            color: _selected?.id == run.id
                ? Theme.of(context).colorScheme.secondaryContainer
                : null,
            child: ListTile(
              leading: Icon(
                run.stale ? Icons.history_toggle_off : _statusIcon(run.status),
              ),
              title: Text('${run.repository} #${run.number}'),
              subtitle: Text(
                '${run.title}\n${run.stale ? 'stale' : run.status} • head ${run.headSha.substring(0, 8)}',
              ),
              isThreeLine: true,
              onTap: () => _open(run),
            ),
          ),
        ),
    ],
  );

  Widget _detail(ManaReviewSchedulerStatus status) {
    if (_detailLoading) return const Center(child: CircularProgressIndicator());
    if (_detailError != null)
      return _empty('Run detail unavailable', '$_detailError');
    final run = _selected;
    if (run == null)
      return _empty(
        'Select a requested review',
        'Familiar reads the durable local inbox. It does not poll GitHub or run providers directly.',
      );
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text(
          '${run.repository} #${run.number}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(run.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SelectableText(
          'Status: ${run.status}${run.stale ? ' (stale)' : ''}\nHead: ${run.headSha}\nReviewer: ${run.reviewer}\nProfile: ${run.profileRevision}\nContext: ${run.contextRevision}\nAttempts: ${run.attempt}',
        ),
        if (run.errorCode != null)
          Text(
            'Error: ${run.errorCode}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            if (!run.stale &&
                ['failed', 'interrupted', 'cancelled'].contains(run.status))
              FilledButton.tonalIcon(
                onPressed: () => _perform(() => widget.client.retry(run)),
                icon: const Icon(Icons.replay),
                label: const Text('Retry'),
              ),
            if (!run.stale && ['queued', 'running'].contains(run.status))
              OutlinedButton.icon(
                onPressed: () => _perform(() => widget.client.cancel(run)),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel'),
              ),
          ],
        ),
        const Divider(height: 32),
        Text('Draft findings', style: Theme.of(context).textTheme.titleLarge),
        if (run.findings.isEmpty)
          const Text('No local draft finding is available.')
        else
          ...run.findings.map(
            (finding) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            finding.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Chip(label: Text(finding.severity)),
                      ],
                    ),
                    SelectableText(finding.body),
                    const SizedBox(height: 8),
                    SelectableText(
                      'Draft ${finding.id} • revision ${run.draftRevision ?? 'unavailable'}',
                    ),
                    const Text(
                      'Publication is not available until Mana advertises a configured external publication boundary. Automatic analysis never publishes.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (run.publicationStatus != null)
          Text('Publication: ${run.publicationStatus}'),
      ],
    );
  }

  Future<void> _open(ManaReviewRun summary) async {
    setState(() {
      _detailLoading = true;
      _detailError = null;
    });
    try {
      final run = await widget.client.show(summary.id);
      if (mounted) setState(() => _selected = run);
    } catch (error) {
      if (mounted) setState(() => _detailError = error);
    } finally {
      if (mounted) setState(() => _detailLoading = false);
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
      _reload();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Widget _empty(String title, String message, {VoidCallback? retry}) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (retry != null)
              TextButton(onPressed: retry, child: const Text('Retry')),
          ],
        ),
      ),
    ),
  );

  IconData _statusIcon(String status) => switch (status) {
    'completed' => Icons.check_circle_outline,
    'running' => Icons.play_circle_outline,
    'failed' || 'interrupted' => Icons.error_outline,
    'cancelled' => Icons.cancel_outlined,
    _ => Icons.schedule,
  };
}

class _ReviewHome {
  const _ReviewHome(this.status, this.inbox);
  final ManaReviewSchedulerStatus status;
  final ManaReviewInbox inbox;
}
