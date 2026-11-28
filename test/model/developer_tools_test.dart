import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/logic/connectivity_service.dart';
import '../../lib/logic/game_state_storage.dart';
import '../../lib/model/app_model.dart';

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
