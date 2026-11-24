import 'package:material_ui/material_ui.dart';

import '../../ui/game_art.dart';
import '../../ui/game_ui.dart';
import '../store_view.dart';

/// Shows the item, the exact shortfall and one clear next step. It never
/// spends coins on the player's behalf after they top up.
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
  final action = await showGameDialog<String>(
    context: context,
    builder: (dialog) {
      final p = dialog.palette;
      return GameDialog(
        art: GameArt(ArtKind.coinStack2, palette: p, size: 64),
        title: itemName,
        child: Semantics(
          label: 'You need $shortfall more coins',
          excludeSemantics: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: p.quiet,
                  borderRadius: BorderRadius.circular(GameTokens.pillRadius),
                  border: Border.all(color: p.cardEdge),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CoinMark(size: 20),
                    const SizedBox(width: 6),
                    Text(
                      '$shortfall short',
                      style: TextStyle(
                        color: p.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          ActionPill(label: 'Not now', onTap: () => Navigator.pop(dialog)),
          ActionPill(
            label: 'Get coins',
            tone: ActionTone.primary,
            onTap: () => Navigator.pop(dialog, 'coins'),
          ),
        ],
      );
    },
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
