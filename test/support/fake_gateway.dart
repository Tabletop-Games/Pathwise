import 'package:flutter/foundation.dart';

import '../../lib/online/api_client.dart';
import '../../lib/online/online_service.dart';

/// Records commands and answers like the server would for the cases tested.
class FakeGateway extends ChangeNotifier implements OnlineGateway {
  bool connected = true;
  bool rewardVerified = true;
  final commands = <({String type, Map<String, Object?> args, String? op})>[];
  final rejectTypes = <String, String>{};
  Map<String, dynamic>? wallet;
  void Function(Map<String, dynamic>)? onWallet;
  int refreshes = 0;
  final rewardStarts = <String>[];

  void setConnected(bool value) {
    connected = value;
    notifyListeners();
  }

  @override
  bool get canPlay => connected;

  @override
  String? get billingAccount => 'a' * 64;

  @override
  bool get gamesRecoveryAvailable => false;

  @override
  Future<bool> linkGames() async => false;

  @override
  Future<CommandResult> command(
    String type,
    Map<String, Object?> args, {
    String? op,
    bool durable = true,
  }) async {
    commands.add((type: type, args: args, op: op));
    if (!connected) return CommandResult.pending;
    final error = rejectTypes[type];
    if (error != null) {
      return CommandResult(ok: false, status: 422, error: error);
    }
    final body = <String, dynamic>{
      if (wallet != null) 'wallet': wallet,
      if (type == 'attack.start')
        'run': {
          'id': 'v2-serverrun01',
          'minutes': args['minutes'],
          'remainingMs': 60000,
          'clears': <int>[],
          'finished': false,
          'unassisted': true,
          'previousBest': 0,
        },
    };
    if (wallet != null) onWallet?.call(wallet!);
    return CommandResult(ok: true, status: 200, body: body);
  }

  List<String> get types => [for (final c in commands) c.type];

  @override
  Future<String?> startReward(String placement, {String? kind}) async {
    if (!connected) return null;
    rewardStarts.add(placement);
    return 'e' * 64;
  }

  @override
  Future<bool> awaitReward(String token) async => rewardVerified;

  @override
  Future<ApiResponse> verifyPurchase(String product, String token) async =>
      const ApiResponse(200, {'id': 'grant'});

  @override
  Future<bool> refreshState() async {
    refreshes++;
    return connected;
  }
}

/// A minimal authoritative wallet in the server's response format.
Map<String, dynamic> serverWallet({
  int coins = 50,
  int hints = 3,
  bool removeAds = false,
  bool premium = false,
  bool themePass = false,
  List<String> themes = const ['field', 'blackwater', 'terracotta', 'signal'],
  Map<String, dynamic>? pendingWheel,
  Map<String, int> limits = const {'coinAds': 6, 'hintAds': 5, 'boostAds': 3},
}) => {
  'serverNow': DateTime(2026, 11, 22).millisecondsSinceEpoch,
  'coins': coins,
  'earned': coins,
  'spent': 0,
  'hints': hints,
  'equipped': 'field',
  'themes': themes,
  'entitlements': {
    'removeAds': removeAds,
    'premium': premium,
    'themePass': themePass || premium,
    'adFree': removeAds || premium,
  },
  'research': <String, int>{},
  'inventory': <String, int>{},
  'active': <String, int>{},
  'streak': {'count': 0, 'longest': 0, 'freezes': 0, 'days': <String, String>{}},
  'achievements': <String>[],
  'counters': {'levelsSolved': 0, 'precision': 0, 'eligibleDailies': 0},
  'wheel': {
    'freeInMs': 0,
    'videosRemaining': 6,
    'pending': pendingWheel,
    'prizes': [
      {'id': 'sprout', 'label': '8 coins', 'coins': 8},
      {'id': 'summit', 'label': '100 coins', 'coins': 100},
    ],
  },
  'crates': {'nextInMs': 999999, 'legendary': 0},
  'limits': limits,
  'recent': [
    {'id': 'starter', 'label': 'Welcome coins', 'amount': coins, 'at': 1},
  ],
};
