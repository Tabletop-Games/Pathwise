import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import '../model/progression.dart';

class CrateAccess extends StatelessWidget {
  const CrateAccess({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.select(
      (AppModel model) => model.unopenedCrates.length,
    );
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -.24),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: count == 0
          ? const SizedBox.shrink()
          : Semantics(
              key: ValueKey(count),
              liveRegion: true,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () async {
                  if (ModalRoute.isCurrentOf(context) != true) return;
                  final model = context.read<AppModel>();
                  model.setCrateInventoryVisible(true);
                  try {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const CratesView()),
                    );
                  } finally {
                    model.setCrateInventoryVisible(false);
                  }
                },
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text(
                  count == 1
                      ? 'Supply crate ready'
                      : '$count supply crates ready',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
    );
  }
}

class CratesView extends StatefulWidget {
  const CratesView({super.key});

  @override
  State<CratesView> createState() => _CratesViewState();
}

class _CratesViewState extends State<CratesView> {
  String? _opening;
  int? _award;

  Future<void> _open(AppModel model, Crate crate) async {
    setState(() => _opening = crate.id);
    final saved = await model.claimCrate(crate.id);
    if (!mounted) return;
    setState(() {
      _opening = null;
      if (saved) _award = crate.coins;
    });
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The crate could not be opened. Check your save and try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final crates = model.unopenedCrates;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Supply crates')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 510),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  '${crates.length} unopened · ${model.coinBalance} coins',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (_award case final coins?)
                  Semantics(
                    liveRegion: true,
                    child: Card(
                      color: theme.colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '+$coins coins from your supply crate',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (crates.isEmpty && _opening == null)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'No unopened crates. Earn your next crate in Levels or the Daily Challenge.',
                    ),
                  ),
                for (final crate in crates)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(switch (crate.rarity) {
                            CrateRarity.common => Icons.inventory_2_outlined,
                            CrateRarity.uncommon => Icons.all_inbox_rounded,
                            CrateRarity.rare => Icons.diamond_outlined,
                            CrateRarity.legendary => Icons.auto_awesome_rounded,
                          }, color: theme.colorScheme.primary),
                          const SizedBox(height: 8),
                          Text(
                            '${crate.rarity.name[0].toUpperCase()}${crate.rarity.name.substring(1)} supply crate',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _opening != null || model.storageError
                                ? null
                                : () => _open(model, crate),
                            icon: const Icon(Icons.lock_open_rounded),
                            label: Text(
                              _opening == crate.id ? 'Opening…' : 'Open crate',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
