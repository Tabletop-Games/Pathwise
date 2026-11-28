import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

class PlayGames {
  static const enabled = bool.fromEnvironment('PATHWISE_GAMES_ENABLED');
  static const _channel = MethodChannel('com.shenmareparas.pathwise/games');
  static Map<String, String> _ids(String config) {
    try {
      return Map<String, String>.from(jsonDecode(config) as Map);
    } catch (_) {
      return {};
    }
  }

  static final boards = _ids(
    const String.fromEnvironment('PATHWISE_GAMES_LEADERBOARDS'),
  );
  static String? timeAttackBoard(int minutes) =>
      boards['Time Attack · $minutes min'];
  static final achievements = _ids(
    const String.fromEnvironment('PATHWISE_GAMES_ACHIEVEMENTS'),
  );

  static Future<T?> call<T>(String method, [Map<String, String>? args]) async {
    if (!enabled) return null;
    try {
      return await _channel
          .invokeMethod<T>(method, args)
          .timeout(const Duration(seconds: 25));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  static Future<bool> isSignedIn() async => await call<bool>('status') == true;

  static Future<bool> signIn() async => await call<bool>('signIn') == true;

  static Future<bool> openLeaderboard(String boardId) async =>
      await call<bool>('leaderboard', {'id': boardId}) == true;

  static Future<bool> submitTimeAttackScore(int minutes, int score) async {
    final board = timeAttackBoard(minutes);
    if (board == null || !enabled) return false;
    return await call<bool>('submitScore', {'id': board, 'score': '$score'}) ==
        true;
  }
}
