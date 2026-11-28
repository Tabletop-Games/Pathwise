import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pathwise/logic/connectivity_service.dart';
import 'package:pathwise/logic/game_state_storage.dart';
import 'package:pathwise/model/app_model.dart';
import 'package:pathwise/views/connection_view.dart';
import 'package:provider/provider.dart';

class _FailingStorage extends GameStateStorage {
  bool fail = false;

  @override
  Future<Map<String, dynamic>> load() async => {};

  @override
  Future<void> save(String payload) async {
    if (fail) throw StateError('disk full');
  }
}

void main() {
  testWidgets('ConnectionGate shows again on a second offline period', (
    tester,
  ) async {
    var online = false;
    var now = DateTime.utc(2026, 11, 27);
    final connectivity = ConnectivityService(
      probe: () async => online,
      now: () => now,
      confirmDelay: const Duration(seconds: 4),
    );
    final model = AppModel(storage: _FailingStorage(), snapshot: {});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: model),
          ChangeNotifierProvider.value(value: connectivity),
        ],
        child: MaterialApp(
          home: ConnectionGate(
            connectivity: connectivity,
            child: const Scaffold(body: Text('Home')),
          ),
        ),
      ),
    );

    // First offline period (2 failed probes >= 4s apart).
    await connectivity.check();
    now = now.add(const Duration(seconds: 5));
    await connectivity.check();
    await tester.pump();
    await tester.pump();
    expect(find.byType(ConnectionPane), findsOneWidget);

    // Back online -> hides overlay and resets period flag.
    online = true;
    await connectivity.check();
    await tester.pump();
    await tester.pump();
    expect(find.byType(ConnectionPane), findsNothing);

    // Second offline period -> shows overlay again.
    online = false;
    await connectivity.check();
    now = now.add(const Duration(seconds: 5));
    await connectivity.check();
    await tester.pump();
    await tester.pump();
    expect(find.byType(ConnectionPane), findsOneWidget);

    connectivity.dispose();
    model.dispose();
  });
}
