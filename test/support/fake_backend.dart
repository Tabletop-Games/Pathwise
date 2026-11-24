import 'dart:convert';

import '../../lib/online/api_client.dart';

/// A scriptable stand-in for the Pathwise backend at the HTTP boundary. It
/// records requests and de-duplicates command operation ids like the server.
class FakeBackend implements HttpTransport {
  static const serverNow = 1800000000000;

  bool offline = false;
  bool down = false;
  bool internet = true;
  bool requireAttestation = false;
  bool refreshRevoked = false;
  bool rewardVerified = true;
  int rewardPolls = 0;
  int verifiedAfterPolls = 1;
  int minBuild = 0;
  int failNextCommands = 0;
  int tokenTtlMs = 15 * 60 * 1000;
  int sessions = 0;
  int registrations = 0;
  String env = 'development';
  final rejected = <String, int>{};
  final requests = <String>[];
  final executed = <Map<String, dynamic>>[];
  final seen = <String, Map<String, dynamic>>{};
  final revokedTokens = <String>{};
  String? lastToken;
  int coins = 50;

  Map<String, dynamic> wallet() => {
    'rev': 1,
    'serverNow': serverNow,
    'day': '2027-01-15',
    'coins': coins,
    'earned': coins,
    'spent': 0,
    'hints': 3,
    'equipped': 'field',
    'themes': ['field', 'blackwater', 'terracotta', 'signal'],
    'entitlements': {
      'themePass': false,
      'removeAds': false,
      'premium': false,
      'adFree': false,
    },
    'research': <String, int>{},
    'inventory': <String, int>{},
    'active': <String, int>{},
    'streak': {'count': 0, 'longest': 0, 'freezes': 0, 'days': {}},
    'achievements': <String>[],
    'counters': {'levelsSolved': 0, 'precision': 0, 'eligibleDailies': 0},
    'wheel': {
      'freeInMs': 0,
      'videosRemaining': 6,
      'pending': null,
      'prizes': [
        {'id': 'sprout', 'label': '8 coins', 'coins': 8},
      ],
    },
    'crates': {'nextInMs': 60000, 'offersRemaining': 8, 'legendary': 0},
    'limits': {
      'coinAds': 6,
      'hintAds': 5,
      'boostAds': 3,
      'tripleAvailable': false,
    },
    'recent': [
      {'id': 'starter', 'label': 'Welcome coins', 'amount': 50, 'at': serverNow},
    ],
    'billingAccount': 'a' * 64,
  };

  Map<String, dynamic> progress() => {
    'rev': 1,
    'results': <String, dynamic>{},
    'stages': <String, dynamic>{},
    'highestUnlocked': 1,
    'tutorials': <String, String>{},
    'attempts': <String, dynamic>{},
    'prefs': {'haptics': true, 'suggestSharing': true},
    'attackHistory': <Object>[],
    'attack': null,
  };

  /// Round-trips through JSON so tests see exactly what the app would decode.
  ApiResponse _json(int status, Map<String, dynamic> body) => ApiResponse(
    status,
    jsonDecode(jsonEncode(body)) as Map<String, dynamic>,
  );

  Map<String, dynamic> _session() {
    sessions++;
    return {
      'token': 'token-$sessions',
      'expiresAt': serverNow + tokenTtlMs,
    };
  }

  @override
  Future<ApiResponse> send(
    String method,
    Uri url, {
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    if (url.host == 'www.gstatic.com') {
      return internet
          ? const ApiResponse(204, {})
          : const ApiResponse(0, {}, failure: ApiFailure.noInternet);
    }
    if (offline) {
      return const ApiResponse(0, {}, failure: ApiFailure.noInternet);
    }
    final path = url.path;
    requests.add('$method $path');
    if (down) {
      return const ApiResponse(
        0,
        {},
        failure: ApiFailure.backendUnavailable,
      );
    }
    final token = headers['authorization']?.replaceFirst('Bearer ', '');
    final data = body == null
        ? <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;
    final build = int.tryParse(headers['x-pathwise-build'] ?? '') ?? 0;
    if (path == '/v1/config') {
      if (minBuild > 0 && build < minBuild) {
        return _json(426, {'error': 'update_required'});
      }
      return _json(200, {'env': env});
    }
    if (path == '/v1/ping') return _json(200, {'serverNow': serverNow});
    if (path == '/v1/auth/challenge') {
      return _json(200, {
        'challenge': 'challenge',
        'nonce': 'nonce',
        'required': requireAttestation,
      });
    }
    if (path == '/v1/auth/register') {
      registrations++;
      return _json(201, {
        'playerId': 'p_test$registrations',
        'session': _session(),
        'refresh': 'abcdabcdabcdabcd.${'b' * 64}',
        'serverNow': serverNow,
      });
    }
    if (path == '/v1/auth/refresh') {
      if (refreshRevoked) return _json(401, {'error': 'session_expired'});
      return _json(200, {
        'session': _session(),
        'refresh': 'abcdabcdabcdabcd.${'c' * 64}',
        'serverNow': serverNow,
      });
    }
    if (token == null || revokedTokens.contains(token)) {
      return _json(401, {'error': 'session_expired'});
    }
    lastToken = token;
    if (path == '/v1/state') {
      return _json(200, {
        'wallet': wallet(),
        'progress': progress(),
        'serverNow': serverNow,
      });
    }
    if (path == '/v1/command') {
      if (failNextCommands > 0) {
        failNextCommands--;
        return _json(503, {'error': 'service_unavailable'});
      }
      final op = data['op'] as String;
      final type = data['type'] as String;
      if (seen.containsKey(op)) {
        return _json(200, {...seen[op]!, 'replayed': true});
      }
      if (rejected.containsKey(type)) {
        return _json(rejected[type]!, {'error': 'invalid_route'});
      }
      executed.add(data);
      final result = {'wallet': wallet()};
      seen[op] = result;
      return _json(200, result);
    }
    if (path.startsWith('/v1/rewards/start/')) {
      return _json(200, {'token': 'f' * 64});
    }
    if (path.startsWith('/v1/rewards/status/')) {
      rewardPolls++;
      return rewardVerified && rewardPolls >= verifiedAfterPolls
          ? _json(200, {'verified': true})
          : _json(202, {'pending': true});
    }
    if (path == '/v1/play/verify') {
      return _json(200, {
        'id': 'grant-1',
        'product': data['product'],
        'wallet': wallet(),
      });
    }
    return _json(404, {'error': 'not_found'});
  }
}
