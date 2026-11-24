import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../logic/ad_service.dart';
import '../../logic/billing_service.dart';
import '../../model/app_model.dart';
import '../store_view.dart';

Future<void> showInsufficientCoins(
  BuildContext context, {
  required String itemName,
  required int requiredCoins,
  required int currentBalance,
}) async {
  final shortfall = (requiredCoins - currentBalance).clamp(0, requiredCoins);
  final billing = context.read<BillingService>();
  final ads = context.read<AdService>();
  final model = context.read<AppModel>();
  final canGetCoins =
      billing.enabled &&
      billing.products.any((product) => consumable(product.id));
  final canEarnCoins = ads.enabled && model.canEarnAdBonus;
  final action = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Not enough coins'),
      content: Text(
        '$itemName costs $requiredCoins coins.\n\nYour balance: $currentBalance coins\nYou need $shortfall more coins.',
      ),
      actions: [
        if (canGetCoins)
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'packs'),
            child: const Text('Get Coins'),
          ),
        if (canEarnCoins)
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'earn'),
            child: const Text('Earn Coins'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Not Now'),
        ),
      ],
    ),
  );
  if (!context.mounted || action == null) return;
  final section = action == 'packs'
      ? StoreSection.coinPacks
      : StoreSection.earnCoins;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => StoreView(section: section, coinShortfall: shortfall),
    ),
  );
}
