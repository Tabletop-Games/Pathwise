import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/logic/social_sharing.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/model/native_achievements.dart';
import 'package:pathwise/views/share_view.dart';

import '../support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final daily = ShareResult.daily(
    '2026-11-23',
    time: const Duration(seconds: 102),
    hints: 2,
    newBest: false,
  );

  test(
    'messages contain real result fields without puzzle or account data',
    () {
      final results = [
        (daily, ['23 Nov 2026', '1m 42s', 'Hints used: 2']),
        (
          ShareResult.attack(score: 1800, puzzles: 18, newBest: true),
          ['1800 points', '18 puzzles', 'personal best'],
        ),
        (
          ShareResult.level(level: 500, total: 499),
          ['Level 500', '499 levels'],
        ),
        (
          ShareResult.achievement('Field Specialist', 'Earn four field marks.'),
          ['Field Specialist', 'Earn four field marks'],
        ),
        (ShareResult.research('Coin Magnet', 10), ['rank 10', 'Coin Magnet']),
        (ShareResult.cosmetic('High Pass'), ['High Pass']),
      ];
      for (final (result, expected) in results) {
        for (final destination in ShareDestination.values) {
          final message = ShareContentBuilder.message(result, destination);
          for (final text in expected) {
            expect(message, contains(text));
          }
          expect(ShareLinks.playStore.allMatches(message), hasLength(1));
          expect(message, isNot(contains(RegExp('seed|coordinates|playerId'))));
        }
      }
      expect(ShareLinks.playStore, endsWith('id=com.shenmareparas.pathwise'));
      expect(SharePromptPolicy.levelMilestone(11), false);
      expect(SharePromptPolicy.levelMilestone(10500), true);
    },
  );

  test('web destinations preserve punctuation and X keeps the invitation', () {
    final result = ShareResult.achievement('Rank & file #1', 'Nice? ✓');
    final telegram = ShareContentBuilder.web(
      result,
      ShareDestination.telegram,
    )!;
    expect(telegram.host, 't.me');
    expect(telegram.queryParameters['url'], ShareLinks.playStore);
    expect(telegram.queryParameters['text'], contains('Rank & file #1'));
    expect(
      telegram.queryParameters['text'],
      isNot(contains(ShareLinks.playStore)),
    );
    final linkedIn = ShareContentBuilder.web(
      result,
      ShareDestination.linkedin,
    )!;
    expect(linkedIn.queryParameters, {'url': ShareLinks.playStore});
    final long = ShareResult.achievement('界' * 200, 'A very long award');
    final x = ShareContentBuilder.web(long, ShareDestination.x)!;
    expect(x.host, 'twitter.com');
    final text = x.queryParameters['text']!;
    final weight = text.runes.fold(
      0,
      (sum, rune) => sum + (rune <= 127 ? 1 : 2),
    );
    expect(text, contains('Think you can unlock it too?'));
    expect(
      weight + 1 + ShareContentBuilder.xShortenedLinkLength,
      lessThanOrEqualTo(280),
    );
  });

  test(
    'WhatsApp and missing web app fall back to plain-text Android chooser',
    () async {
      const service = ShareDestinationService();
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('com.shenmareparas.pathwise/share');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'chooser';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect(await service.open(daily, ShareDestination.whatsapp), true);
      expect(calls.map((e) => e.method), ['whatsapp', 'chooser']);
      expect(calls[1].arguments['content'], contains('23 Nov 2026'));
      expect(calls[1].arguments['content'], contains(ShareLinks.playStore));
      calls.clear();
      expect(await service.open(daily, ShareDestination.telegram), true);
      expect(calls.map((e) => e.method), ['web', 'chooser']);
      messenger.setMockMethodCallHandler(channel, null);
      expect(await service.open(daily, ShareDestination.android), false);
    },
  );

  testWidgets(
    'LinkedIn copies the caption first and previews on a small screen',
    (tester) async {
      final events = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('com.shenmareparas.pathwise/share');
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          events.add(call.arguments['text'] as String);
        }
        return null;
      });
      messenger.setMockMethodCallHandler(channel, (call) async {
        events.add(call.arguments['content'] as String);
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      await tester.binding.setSurfaceSize(const Size(320, 530));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: ShareView(result: daily),
        ),
      );
      await tester.tap(find.text('LinkedIn'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('paste it into your LinkedIn post'),
        findsOneWidget,
      );
      final open = find.text('Copy Caption and Open LinkedIn');
      await tester.ensureVisible(open);
      await tester.pumpAndSettle();
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(events.first, contains('Hints used: 2'));
      expect(events.first, contains(ShareLinks.playStore));
      expect(Uri.parse(events[1]).host, 'www.linkedin.com');
      final link = find.text('Copy Link');
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(events.last, ShareLinks.playStore);
      final message = find.text('Copy Message');
      await tester.ensureVisible(message);
      await tester.pumpAndSettle();
      await tester.tap(message);
      await tester.pumpAndSettle();
      expect(events.last, events.first);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'setting disables celebration suggestions without spending coins',
    (tester) async {
      final model = AppModel(storage: MemoryStorage(), snapshot: {});
      final balance = model.coinBalance;
      model.recentAchievements = [nativeAchievements.first];
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AchievementCelebration(model))),
      );
      expect(find.byTooltip('Share Achievement'), findsNothing);
      model.setSharingSuggestions(false);
      await model.flush();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AchievementCelebration(model))),
      );
      expect(find.byTooltip('Share Achievement'), findsNothing);
      expect(find.text('First Steps'), findsOneWidget);
      expect(model.coinBalance, balance);
      final restored = AppModel(
        storage: MemoryStorage(),
        snapshot: await model.storage.load(),
      );
      expect(restored.suggestSharing, false);
      model.dispose();
      restored.dispose();
    },
  );
}
