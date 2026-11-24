import 'package:material_ui/material_ui.dart';

import '../store_view.dart';

Future<void> showInsufficientCoins(
  BuildContext context, {
  required String itemName,
  required int requiredCoins,
  required int currentBalance,
  VoidCallback? onBeforeStore,
}) async {
  final shortfall = requiredCoins > currentBalance
      ? requiredCoins - currentBalance
      : 0;
  final action = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Not enough coins'),
      content: Text(
        '$itemName costs $requiredCoins coins.\n\nYour balance: $currentBalance coins\nYou need $shortfall more coins.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, 'coins'),
          child: const Text('View Coins'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Not Now'),
        ),
      ],
    ),
  );
  if (!context.mounted || action == null) return;
  onBeforeStore?.call();
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          StoreView(section: StoreSection.coins, coinShortfall: shortfall),
    ),
  );
}
