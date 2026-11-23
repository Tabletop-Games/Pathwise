import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../model/app_model.dart';

class PlayGames {
  static const enabled = bool.fromEnvironment('PATHWISE_GAMES_ENABLED');
  static const _channel = MethodChannel('games.tabletop.pathwise/games');
  static const _webClient = String.fromEnvironment(
    'PATHWISE_GAMES_WEB_CLIENT_ID',
  );
  static final _linkUrl = Uri.tryParse(
    const String.fromEnvironment('PATHWISE_REWARD_URL'),
  );

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

  static Future<bool> link(AppModel model) async {
    final url = _linkUrl;
    if (_webClient.isEmpty ||
        url == null ||
        url.scheme != 'https' ||
        url.userInfo.isNotEmpty)
      return false;
    final secret = await model.billingProfile();
    final code = await call<String>('serverCode', {'client': _webClient});
    if (secret == null || code == null) return false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(url.replace(path: '/v1/games/link'));
      req.followRedirects = false;
      req.headers.contentType = ContentType.json;
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      req.write(jsonEncode({'code': code}));
      final response = await req.close().timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
