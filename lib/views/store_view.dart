import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/ad_service.dart';
import '../logic/billing_service.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy.dart';
import '../model/user_preferences.dart';

class StoreView extends StatefulWidget {
  const StoreView({super.key});

  @override
  State<StoreView> createState() => _StoreViewState();
}

class _StoreViewState extends State<StoreView> {
  PathwiseTheme? _preview;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final billing = context.watch<BillingService>();
    final ads = context.watch<AdService>();
    final preview = _preview ?? model.theme;
    final palette = BoardPalette.palettes[preview]!;
    return Theme(
      data: palette.theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cosmetics'),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 14),
              child: TextButton.icon(
                icon: const Icon(Icons.toll_rounded),
                label: Text(
                  '${model.coinBalance}',
                  semanticsLabel: '${model.coinBalance} coins',
                ),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => const _HistoryView()),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ThemePreview(theme: preview, palette: palette),
                  const SizedBox(height: 17),
                  for (final theme in PathwiseTheme.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        tileColor: palette.surface,
                        selectedTileColor: palette.covered,
                        selected: preview == theme,
                        onTap: () => setState(() => _preview = theme),
                        leading: _Swatch(
                          palette: BoardPalette.palettes[theme]!,
                        ),
                        title: Text(theme.label),
                        subtitle: Text(
                          model.theme == theme
                              ? 'Equipped'
                              : model.ownsTheme(theme)
                              ? 'Owned'
                              : '${economy.themePrice(theme)} coins',
                        ),
                        trailing: model.theme == theme
                            ? const Icon(Icons.check_rounded)
                            : TextButton(
                                onPressed: model.ownsTheme(theme)
                                    ? () => model.setTheme(theme)
                                    : () => _confirm(context, model, theme),
                                child: Text(
                                  model.ownsTheme(theme) ? 'Equip' : 'Unlock',
                                ),
                              ),
                      ),
                    ),
                  if (ads.enabled) ...[
                    const SizedBox(height: 12),
                    ListTile(
                      title: Text(
                        'Optional video · +${economy.rewardedAdCoins} coins',
                      ),
                      subtitle: Text(
                        !model.canEarnAdBonus
                            ? 'Daily limit reached'
                            : ads.message ??
                                  (ads.videoReady
                                      ? 'Video ready'
                                      : 'Availability varies'),
                      ),
                      trailing: TextButton(
                        onPressed: !model.canEarnAdBonus
                            ? null
                            : ads.videoReady
                            ? () => ads.watchVideo(model.grantAdBonus)
                            : () => ads.prepare(
                                canPresent: () =>
                                    context.mounted &&
                                    ModalRoute.isCurrentOf(context) == true,
                              ),
                        child: Text(ads.videoReady ? 'Watch' : 'Check'),
                      ),
                    ),
                    if (ads.privacyRequired)
                      TextButton(
                        onPressed: ads.privacyOptions,
                        child: const Text('Ad privacy choices'),
                      ),
                  ],
                  if (billing.enabled) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Google Play',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final product in billing.products)
                      ListTile(
                        title: Text(storeProducts[product.id]!.label),
                        subtitle: product.id == themePassProduct
                            ? const Text('Unlocks every current theme')
                            : null,
                        trailing: OutlinedButton(
                          onPressed:
                              billing.buying ||
                                  model.storageError ||
                                  (product.id == themePassProduct &&
                                      model.hasThemePass)
                              ? null
                              : () => billing.buy(product),
                          child: Text(
                            product.id == themePassProduct && model.hasThemePass
                                ? 'Owned'
                                : product.price,
                          ),
                        ),
                      ),
                    if (billing.message case final message?)
                      Semantics(liveRegion: true, child: Text(message)),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: billing.buying ? null : billing.restore,
                          child: const Text('Restore purchases'),
                        ),
                        TextButton(
                          onPressed: billing.buying
                              ? null
                              : billing.refreshCatalog,
                          child: const Text('Refresh prices'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    AppModel model,
    PathwiseTheme theme,
  ) async {
    final cost = economy.themePrice(theme);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final enough = model.coinBalance >= cost && !model.storageError;
        return AlertDialog(
          title: Text('Unlock ${theme.label}?'),
          content: Text(
            enough
                ? 'Spend $cost coins to own and equip this theme.'
                : model.storageError
                ? 'Local storage is unavailable. Your wallet has not changed.'
                : 'This theme costs $cost coins. You have ${model.coinBalance}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(enough ? 'Cancel' : 'Close'),
            ),
            if (enough)
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Unlock · $cost'),
              ),
          ],
        );
      },
    );
    if (confirmed == true && mounted && model.unlockTheme(theme)) {
      setState(() => _preview = theme);
    }
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.theme, required this.palette});
  final PathwiseTheme theme;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    const route = [0, 1, 5, 6, 10, 11];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              theme.label,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            for (var row = 0; row < 3; row++)
              Row(
                children: [
                  for (var col = 0; col < 4; col++)
                    Expanded(
                      child: Container(
                        height: 30,
                        alignment: Alignment.center,
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          color: route.contains(row * 4 + col)
                              ? palette.route
                              : palette.tile,
                        ),
                        child: switch (row * 4 + col) {
                          0 => Text(
                            '1',
                            style: TextStyle(color: palette.onRoute),
                          ),
                          11 => Text(
                            '2',
                            style: TextStyle(color: palette.onRoute),
                          ),
                          _ => null,
                        },
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette});
  final BoardPalette palette;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    backgroundColor: palette.route,
    child: CircleAvatar(radius: 7, backgroundColor: palette.accent),
  );
}

class _HistoryView extends StatelessWidget {
  const _HistoryView();

  @override
  Widget build(BuildContext context) {
    final tx = context.watch<AppModel>().transactions;
    return Scaffold(
      appBar: AppBar(title: const Text('Coin history')),
      body: SafeArea(
        child: ListView.builder(
          itemCount: tx.length,
          itemBuilder: (context, index) {
            final entry = tx[index];
            return ListTile(
              title: Text(entry.label),
              subtitle: Text(
                MaterialLocalizations.of(context)
                    .formatCompactDate(entry.date.toLocal()),
              ),
              trailing: Text(
                entry.amount > 0 ? '+${entry.amount}' : '${entry.amount}',
              ),
            );
          },
        ),
      ),
    );
  }
}
