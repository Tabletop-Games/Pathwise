import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../cloud/cloud_save_format.dart';
import '../cloud/cloud_sync_service.dart';

String _when(DateTime? time) {
  if (time == null) return 'Not synced yet';
  final now = DateTime.now();
  final two = (int v) => v.toString().padLeft(2, '0');
  final clock = '${two(time.hour)}:${two(time.minute)}';
  final sameDay =
      time.year == now.year && time.month == now.month && time.day == now.day;
  if (sameDay) return 'Last synced today at $clock';
  return 'Last synced ${time.day}/${time.month}/${time.year} at $clock';
}

String _statusLine(CloudSyncService cloud) => switch (cloud.status) {
  CloudSyncStatus.unsupported => 'Cloud save isn’t available on this device.',
  CloudSyncStatus.signedOut =>
    'Not signed in. Sign in to protect your progress and coins.',
  CloudSyncStatus.idle =>
    cloud.signedIn ? 'Connected to ${cloud.providerName}.' : 'Not signed in.',
  CloudSyncStatus.syncing => 'Syncing your progress…',
  CloudSyncStatus.waitingForNetwork =>
    'Waiting for an internet connection to sync.',
  CloudSyncStatus.conflict =>
    'Your device and the cloud have different progress. Choose which to keep.',
  CloudSyncStatus.damaged =>
    cloud.message ?? 'Your cloud save could not be read.',
  CloudSyncStatus.error => cloud.message ?? 'Sync failed. Try again later.',
};

/// Settings → Cloud save. Shows status and offers sign-in, sync, restore and
/// sign-out. It never shows identifiers, tokens or raw errors.
class CloudSaveSection extends StatelessWidget {
  const CloudSaveSection({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudSyncService?>();
    if (cloud == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final busy = cloud.status == CloudSyncStatus.syncing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        ListTile(
          key: const ValueKey('cloud-save-status'),
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('Cloud save'),
          subtitle: Text(
            '${_statusLine(cloud)}\n${_when(cloud.lastSynced)}',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          isThreeLine: true,
        ),
        if (cloud.status != CloudSyncStatus.unsupported && !cloud.signedIn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton(
              onPressed: busy ? null : cloud.signIn,
              child: const Text('Sign in to save progress'),
            ),
          ),
        if (cloud.signedIn) ...[
          ListTile(
            key: const ValueKey('cloud-sync-now'),
            leading: const Icon(Icons.sync),
            title: const Text('Sync now'),
            enabled: !busy,
            onTap: busy ? null : () => cloud.syncNow(),
          ),
          ListTile(
            key: const ValueKey('cloud-restore'),
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('Restore progress from cloud'),
            subtitle: const Text(
              'Replaces this device’s progress. A backup is kept on this device.',
            ),
            enabled: !busy,
            onTap: busy ? null : () => _confirmRestore(context, cloud),
          ),
          ListTile(
            key: const ValueKey('cloud-sign-out'),
            leading: const Icon(Icons.logout),
            title: const Text('Sign out of Play Games'),
            subtitle: const Text(
              'This device keeps its progress. Signing in again compares it with that account.',
            ),
            enabled: !busy,
            onTap: busy ? null : () => cloud.signOut(),
          ),
        ],
        if (cloud.hasBackup)
          ListTile(
            key: const ValueKey('cloud-restore-backup'),
            leading: const Icon(Icons.history),
            title: const Text('Restore the previous device save'),
            subtitle: const Text(
              'Use the copy this device kept before its last replacement.',
            ),
            onTap: busy ? null : () => _confirmBackup(context, cloud),
          ),
        const Divider(),
      ],
    );
  }

  Future<void> _confirmRestore(
    BuildContext context,
    CloudSyncService cloud,
  ) async {
    final confirmed = await _ask(
      context,
      title: 'Restore from cloud?',
      body: 'This device’s progress will be replaced by your cloud save. The current device progress is kept as a backup.',
      action: 'Restore',
    );
    if (confirmed) await cloud.restoreFromCloud();
  }

  Future<void> _confirmBackup(
    BuildContext context,
    CloudSyncService cloud,
  ) async {
    final confirmed = await _ask(
      context,
      title: 'Restore the previous save?',
      body: 'The progress this device had before its last replacement will return.',
      action: 'Restore',
    );
    if (confirmed) await cloud.restoreBackup();
  }
}

Future<bool> _ask(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result == true;
}

/// Opens the conflict dialog whenever sync needs the player's decision. It
/// sits above the Navigator, so it uses the navigator key.
class CloudChoiceWatcher extends StatefulWidget {
  const CloudChoiceWatcher({
    required this.navigatorKey,
    required this.cloud,
    required this.child,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final CloudSyncService? cloud;
  final Widget? child;

  @override
  State<CloudChoiceWatcher> createState() => _CloudChoiceWatcherState();
}

class _CloudChoiceWatcherState extends State<CloudChoiceWatcher> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    widget.cloud?.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant CloudChoiceWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cloud != widget.cloud) {
      oldWidget.cloud?.removeListener(_changed);
      widget.cloud?.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.cloud?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final cloud = widget.cloud;
    if (cloud == null || cloud.choice == null || _showing) return;
    final context = widget.navigatorKey.currentContext;
    if (context == null) return;
    _showing = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => _ConflictDialog(cloud: cloud),
    ).whenComplete(() => _showing = false);
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}

class _ConflictDialog extends StatelessWidget {
  const _ConflictDialog({required this.cloud});

  final CloudSyncService cloud;

  String _line(SaveSummary summary) =>
      '${summary.coins} coins · ${summary.hints} hints · '
      '${summary.levelsSolved} levels solved · '
      'up to level ${summary.highestLevel}';

  @override
  Widget build(BuildContext context) {
    final choice = cloud.choice;
    if (choice == null) return const SizedBox.shrink();
    final saved = DateTime.fromMillisecondsSinceEpoch(choice.cloud.savedAt);
    return AlertDialog(
      title: const Text('Choose your progress'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Coins and purchases from two devices can’t be combined safely, so please choose one copy. The other is kept as a backup on this device.',
            ),
            const SizedBox(height: 16),
            Text(
              'This device',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(_line(choice.device)),
            const SizedBox(height: 12),
            Text(
              'Cloud save (${saved.day}/${saved.month}/${saved.year})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(_line(choice.cloud)),
            const Divider(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            cloud.resolveChoice(keepDevice: false);
          },
          child: const Text('Use cloud save'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            cloud.resolveChoice(keepDevice: true);
          },
          child: const Text('Keep this device'),
        ),
      ],
    );
  }
}
