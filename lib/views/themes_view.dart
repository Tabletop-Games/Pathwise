import 'dart:math' as math;

import 'package:flutter/services.dart';
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
    final colors = palette.theme.colorScheme;
    final brightness = palette.canvas.computeLuminance() < 0.179
        ? Brightness.light
        : Brightness.dark;
    final systemUi = SystemUiOverlayStyle(
      statusBarColor: palette.canvas,
      statusBarIconBrightness: brightness,
      statusBarBrightness: brightness == Brightness.light
          ? Brightness.dark
          : Brightness.light,
      systemNavigationBarColor: palette.canvas,
      systemNavigationBarIconBrightness: brightness,
      systemNavigationBarContrastEnforced: false,
    );
    return Theme(
      data: palette.theme,
      child: Builder(
        builder: (screenContext) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: systemUi,
          child: Scaffold(
            appBar: AppBar(
              systemOverlayStyle: systemUi,
              title: const Text('Themes'),
              actions: [
                Tooltip(
                  message: 'Open Wallet',
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => _preview = null);
                      Navigator.of(screenContext).push<void>(
                        MaterialPageRoute(builder: (_) => const WalletView()),
                      );
                    },
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final boardSize = math.min(
                        140.0,
                        math.max(48.0, (constraints.maxHeight - 150) / 2),
                      );
                      final largeText =
                          MediaQuery.textScalerOf(context).scale(14) > 21;
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: _ThemePreview(
                              theme: theme,
                              palette: palette,
                              boardSize: boardSize,
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              key: const ValueKey('theme-catalogue'),
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              children: [
                                Material(
                                  color: colors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    children: [
                                      for (final item
                                          in PathwiseTheme.values) ...[
                                        if (item != PathwiseTheme.values.first)
                                          Divider(
                                            height: 1,
                                            indent: 60,
                                            color: colors.outlineVariant,
                                          ),
                                        Semantics(
                                          selected: theme == item,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              ListTile(
                                                key: ValueKey(
                                                  'theme-row-${item.name}',
                                                ),
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                    ),
                                                minVerticalPadding: 4,
                                                selected: theme == item,
                                                selectedColor: colors.onSurface,
                                                selectedTileColor: colors
                                                    .surfaceContainerHighest,
                                                leading: _Swatch(
                                                  palette: BoardPalette
                                                      .palettes[item]!,
                                                ),
                                                title: Text(
                                                  item.label,
                                                  style: TextStyle(
                                                    color: colors.onSurface,
                                                  ),
                                                ),
                                                onTap: () => setState(
                                                  () => _preview = item,
                                                ),
                                                trailing: largeText
                                                    ? null
                                                    : _themeAction(
                                                        screenContext,
                                                        model,
                                                        item,
                                                        colors,
                                                      ),
                                              ),
                                              if (largeText)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 12,
                                                        bottom: 4,
                                                      ),
                                                  child: Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: _themeAction(
                                                      screenContext,
                                                      model,
                                                      item,
                                                      colors,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (model.earnedTheme(theme) &&
                                    economy.themePrice(theme) >= 4500)
                                  ShareResultButton(
                                    result: ShareResult.cosmetic(theme.label),
                                    label: 'Share Theme Discovery',
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_rounded,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                'Equipped',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
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
          ? () {
              model.setTheme(item);
              setState(() => _preview = item);
            }
          : () => _buy(context, model, item, price),
      child: Ink(
        decoration: ShapeDecoration(
          color: background,
          shape: const StadiumBorder(),
        ),
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
        onBeforeStore: () {
          if (mounted) setState(() => _preview = null);
        },
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
  const _ThemePreview({
    required this.theme,
    required this.palette,
    required this.boardSize,
  });
  final PathwiseTheme theme;
  final BoardPalette palette;
  final double boardSize;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            theme.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Center(
            child: SizedBox.square(
              dimension: boardSize,
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
    radius: 18,
    backgroundColor: palette.route,
    child: CircleAvatar(radius: 7, backgroundColor: palette.accent),
  );
}
