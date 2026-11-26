import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Connection state as the game sees it. Wi-Fi or mobile data alone is not
/// enough: the state is based on an actual HTTP round trip.
enum ConnectivityState { checking, online, offline }

/// Reachability probes. Both endpoints are Google's own connectivity-check
/// URLs that return HTTP 204 with no body and no identifiers. A captive portal
/// or a filtered network answers with a redirect or a page, which fails the
/// probe. The developer runs no server for this.
const connectivityProbeUrls = [
  'https://connectivitycheck.gstatic.com/generate_204',
  'https://www.google.com/generate_204',
];

/// Returns true only when one probe URL answers 204 within [timeout].
Future<bool> probeInternet({
  List<String> urls = connectivityProbeUrls,
  Duration timeout = const Duration(seconds: 5),
}) async {
  for (final url in urls) {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      if (response.statusCode == 204) return true;
    } catch (_) {
      // Try the next endpoint.
    } finally {
      client.close(force: true);
    }
  }
  return false;
}

/// The single source of truth for "can the player reach the internet".
///
/// It reports offline only after two failed probes at least [confirmDelay]
/// apart, so a dropped packet does not pause a puzzle. Probing stops while
/// the app is in the background and resumes on foreground.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService({
    required Future<bool> Function() probe,
    DateTime Function()? now,
    this.interval = const Duration(seconds: 20),
    this.confirmDelay = const Duration(seconds: 4),
    this.maxRetryInterval = const Duration(seconds: 15),
  }) : _probe = probe,
       _now = now ?? DateTime.now;

  final Future<bool> Function() _probe;
  final DateTime Function() _now;
  final Duration interval;
  final Duration confirmDelay;
  final Duration maxRetryInterval;

  ConnectivityState _state = ConnectivityState.checking;
  ConnectivityState get state => _state;
  bool get online => _state == ConnectivityState.online;

  int _failures = 0;
  DateTime? _firstFailure;
  int _retries = 0;
  bool _foreground = true;
  bool _checking = false;
  bool _pendingRetry = false;
  bool _disposed = false;
  Timer? _timer;

  /// Starts periodic probing and runs the first check now.
  Future<void> start() async {
    _foreground = true;
    await check();
  }

  /// Runs one probe and updates [state]. Concurrent calls are ignored unless
  /// queued via [retry].
  Future<void> check() async {
    if (_checking || _disposed) return;
    _checking = true;
    bool reachable;
    try {
      reachable = await _probe();
    } catch (_) {
      reachable = false;
    }
    _checking = false;
    if (_disposed) return;
    _record(reachable);
    if (_pendingRetry) {
      _pendingRetry = false;
      await check();
      return;
    }
    _schedule();
  }

  /// Retry button. Restarts backoff and probes immediately.
  Future<void> retry() {
    _retries = 0;
    _timer?.cancel();
    if (_checking) {
      _pendingRetry = true;
      return Future.value();
    }
    return check();
  }

  /// Pauses probing in the background and resumes in the foreground.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    _timer?.cancel();
    if (foreground) {
      unawaited(check());
    }
  }

  void _record(bool reachable) {
    if (reachable) {
      _failures = 0;
      _firstFailure = null;
      _retries = 0;
      _set(ConnectivityState.online);
      return;
    }
    _failures++;
    _firstFailure ??= _now();
    if (_state != ConnectivityState.online) {
      _retries++;
      _set(ConnectivityState.offline);
      return;
    }
    final elapsed = _now().difference(_firstFailure!);
    if (_failures >= 2 && elapsed >= confirmDelay) {
      _retries = 0;
      _set(ConnectivityState.offline);
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_foreground || _disposed) return;
    final Duration delay;
    if (_state == ConnectivityState.online && _failures > 0) {
      delay = confirmDelay;
    } else if (_state == ConnectivityState.online) {
      delay = interval;
    } else {
      final seconds = (2 << _retries.clamp(0, 4)).clamp(2, 60);
      delay = Duration(
        seconds: seconds > maxRetryInterval.inSeconds
            ? maxRetryInterval.inSeconds
            : seconds,
      );
    }
    _timer = Timer(delay, () => unawaited(check()));
  }

  void _set(ConnectivityState value) {
    if (_state == value) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
