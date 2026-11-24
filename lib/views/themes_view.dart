import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../logic/social_sharing.dart';
import '../model/app_model.dart';
import '../model/app_themes.dart';
import '../model/economy.dart';
import '../model/user_preferences.dart';
import 'components/economy_navigation.dart';
import 'components/puzzle_board.dart';
import 'share_view.dart';
import 'wallet_view.dart';

class ThemesView extends StatefulWidget {
  const ThemesView({super.key});

  @override
  State<ThemesView> createState() => _ThemesViewState();
}

class _ThemesViewState extends State<ThemesView> {
  PathwiseTheme? _preview;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final theme = _preview ?? model.theme;
    final palette = BoardPalette.palettes[theme]!;
    return Theme(
      data: palette.theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Themes'),
          actions: [
            Tooltip(
              message: 'Open Wallet',
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const WalletView()),
                ),
                icon: const Icon(Icons.toll_rounded),
                label: Text('${model.coinBalance}'),
              ),
            ),
            const SizedBox(width: 8),
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
                  _ThemePreview(theme: theme, palette: palette),
                  if (model.earnedTheme(theme) &&
                      economy.themePrice(theme) >= 4500)
                    ShareResultButton(
                      result: ShareResult.cosmetic(theme.label),
                      label: 'Share Theme Discovery',
                    ),
                  const SizedBox(height: 16),
                  for (final item in PathwiseTheme.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Builder(
                        builder: (context) {
                          final itemPalette = BoardPalette.palettes[item]!;
                          return Theme(
                            data: itemPalette.theme,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              minVerticalPadding: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              tileColor: itemPalette.surface,
                              onTap: () => setState(() => _preview = item),
                              leading: _Swatch(palette: itemPalette),
                              title: Text(item.label, style: TextStyle(color: itemPalette.ink)),
                              trailing: _themeAction(context, model, item, itemPalette.theme.colorScheme),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _themeAction(
    BuildContext context,
    AppModel model,
    PathwiseTheme item,
    ColorScheme colors,
  ) {
    if (model.theme == item) {
      return Semantics(
        label: '${item.label}, equipped',
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.onSurfaceVariant),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_rounded, size: 16, color: colors.onSurface),
              const SizedBox(width: 4),
              Text('Equipped', style: TextStyle(color: colors.onSurface)),
            ]),
          ),
        ),
      );
    }
    final owned = model.ownsTheme(item);
    final price = economy.themePrice(item);
    final background = owned ? colors.secondary : colors.primary;
    final foreground = owned ? colors.onSecondary : colors.onPrimary;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: foreground,
        shadowColor: Colors.transparent,
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      onPressed: owned
          ? () => model.setTheme(item)
          : () => _buy(context, model, item, price),
      child: Ink(
        decoration: ShapeDecoration(color: background, shape: const StadiumBorder()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(owned ? 'Apply' : '$price coins'),
        ),
      ),
    );
  }

  Future<void> _buy(
    BuildContext context,
    AppModel model,
    PathwiseTheme theme,
    int price,
  ) async {
    if (model.storageError) return;
    if (model.coinBalance < price) {
      await showInsufficientCoins(
        context,
        itemName: theme.label,
        requiredCoins: price,
        currentBalance: model.coinBalance,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Unlock ${theme.label}?'),
        content: Text('Spend $price coins to own and equip this theme.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text('Unlock · $price'),
          ),
        ],
      ),
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
  Widget build(BuildContext context) => DecoratedBox(
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
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: LevelOneBoardPreview(palette: palette),
            ),
          ),
        ],
      ),
    ),
  );
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
