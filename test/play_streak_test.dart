import 'package:flutter_test/flutter_test.dart';

import '../lib/model/play_streak.dart';

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
}
