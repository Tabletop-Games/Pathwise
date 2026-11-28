import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../lib/logic/ad_frequency.dart';
import '../../lib/logic/ad_service.dart';
import '../../lib/logic/billing_service.dart';
import '../../lib/logic/connectivity_service.dart';
import '../../lib/logic/game_controller.dart';
import '../../lib/logic/game_state_storage.dart';
import '../../lib/logic/puzzle.dart';
import '../../lib/logic/tip_tracker.dart';
import '../../lib/model/app_model.dart';
import '../../lib/model/app_themes.dart';
import '../../lib/model/economy.dart';
import '../../lib/model/user_preferences.dart';
import '../../lib/views/components/puzzle_board.dart';
import '../../lib/views/journey_rewards.dart';

class _MemoryStorage extends GameStateStorage {
  String data = '{}';

  @override
  Future<Map<String, dynamic>> load() async =>
      Map<String, dynamic>.from(jsonDecode(data) as Map);

  @override
  Future<void> save(String snapshot) async {
    data = snapshot;
  }
}

void main() {
  test('Developer tools stay disabled by default and ignore mutations', () {
    final model = AppModel(
      storage: _MemoryStorage(),
      snapshot: const {},
      connectivity: ConnectivityService(probe: () async => true),
      today: () => DateTime(2026, 11, 25),
      bootTime: () => (boot: 1, milliseconds: 1000),
    );
    expect(model.developerMode, isFalse);
    final coinsBefore = model.coinBalance;
    model.setDebugResources(coins: 999999, hints: 99);
    model.advanceDebugDay(qualify: true);
    expect(model.coinBalance, coinsBefore);
    model.dispose();
  });
}
