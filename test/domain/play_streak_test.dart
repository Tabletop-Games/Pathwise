import 'package:flutter_test/flutter_test.dart';

import '../../lib/model/play_streak.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../lib/logic/ad_service.dart';
import '../../lib/logic/billing_service.dart';
import '../../lib/logic/notification_service.dart';
import '../../lib/logic/puzzle.dart';
import '../../lib/logic/star_rating.dart';
import '../../lib/main.dart' show PathwiseScrollBehavior;
import '../../lib/model/app_model.dart';
import '../../lib/model/app_themes.dart';
import '../../lib/model/economy.dart';
import '../../lib/model/game_state.dart';
import '../../lib/model/notification_preferences.dart';
import '../../lib/model/user_preferences.dart';
import '../../lib/ui/game_ui.dart';
import '../../lib/viewmodels/statistics_viewmodel.dart';
import '../../lib/views/campaign_journey_view.dart';
import '../../lib/views/components/puzzle_board.dart';
import '../../lib/views/components/tip_art.dart';
import '../../lib/views/developer_view.dart';
import '../../lib/views/progression_view.dart';
import '../../lib/views/puzzle_view.dart';
import '../../lib/views/store_view.dart';
import '../support/fixtures.dart' show MemoryStorage;

void main() {
  test('freezes bridge missed days without incrementing the streak', () {
    final streak = PlayStreak({});
    expect(streak.qualify('2026-10-31'), true);
    streak.freezes = 2;
    expect(streak.qualify('2026-11-03'), true);
    expect(streak.freezes, 0);
    expect(streak.count, 2);
    expect(streak.days['2026-11-01'], 'protected');
    expect(streak.days['2026-11-02'], 'protected');
    final restored = PlayStreak(streak.toJson());
    expect(restored.qualify('2026-11-03'), false);
    expect(restored.qualify('2026-11-02'), false);
    restored.reconcile('2026-11-05');
    expect(restored.count, 0);
    restored.freezes++;
    expect(restored.qualify('2026-11-05'), true);
    expect(restored.count, 1);
    expect(restored.longest, 2);
    expect(restored.freezes, 1);
  });

  test('longestPlayStreak is never less than current play streak', () {
    final model = AppModel(
      storage: MemoryStorage(),
      snapshot: {
        'playStreak': {
          'count': 2,
          'longest': 2,
          'freezes': 0,
          'lastEarned': '2026-11-27',
          'checkedThrough': '2026-11-27',
        },
      },
      today: () => DateTime(2026, 11, 27),
    );
    final summary = StatisticsSummary.fromModel(model);
    expect(summary.dayStreak, 2);
    expect(summary.longestPlayStreak, 2);
    expect(summary.dailyStreak, 0);
    expect(summary.longestStreak, 0);
    model.dispose();
  });
}
