import 'dart:convert';
import 'dart:io';

enum RewardPlacement { coins, hint, refill, wheel, crate }

class RewardVerifier {
  RewardVerifier(this.profile);
  final Future<String?> Function() profile;
  final _url = Uri.tryParse(
    const String.fromEnvironment('PATHWISE_REWARD_URL'),
  );
  bool get enabled =>
      _url?.scheme == 'https' &&
      _url!.host.isNotEmpty &&
      _url.userInfo.isEmpty &&
      !_url.hasQuery &&
      !_url.hasFragment;

  Future<Map<String, dynamic>?> _request(
    String method,
    String path,
    String secret,
  ) async {
    if (!enabled) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(
        method,
        _url!.replace(path: '/v1/rewards/$path'),
      );
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != 200) return null;
      return jsonDecode(
        await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 5)),
      ) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<({String token, String secret})?> start(
    RewardPlacement placement,
  ) async {
    if (!enabled) return null;
    final secret = await profile();
    if (secret == null) return null;
    final data = await _request('POST', 'start/${placement.name}', secret);
    final token = data?['token'];
    return token is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(token)
        ? (token: token, secret: secret)
        : null;
  }

  Future<Map<String, dynamic>?> fortune() async {
    if (!enabled) return null;
    final secret = await profile();
    return secret == null ? null : _request('GET', 'wheel', secret);
  }

  Future<String?> confirm(
    RewardPlacement placement,
    String token,
    String secret,
  ) async {
    for (var attempt = 0; attempt < 15; attempt++) {
      final data = await _request('GET', 'status/$token', secret);
      final receipt = data?['id'];
      if (data?['placement'] == placement.name &&
          receipt is String &&
          RegExp(r'^[a-f0-9]{64}$').hasMatch(receipt))
        return receipt;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return null;
  }
}
