import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'identity_store.dart';

/// What the player needs to be told. Never contains technical detail.
enum ConnectionPhase {
  starting,
  online,
  noInternet,
  backendUnavailable,
  authFailed,
  sessionExpired,
  updateRequired,
  notConfigured,
}

final class CommandResult {
  const CommandResult({
    required this.ok,
    this.queued = false,
    this.status = 0,
    this.error,
    this.body = const {},
  });

  /// The server accepted (or replayed) the command.
  final bool ok;

  /// The command is saved for delivery and has not been applied yet.
  final bool queued;
  final int status;
  final String? error;
  final Map<String, dynamic> body;

  static const pending = CommandResult(ok: false, queued: true);
}

/// The surface AppModel and the ad and billing services depend on.
abstract class OnlineGateway implements Listenable {
  /// True only while an authenticated session and a reachable backend exist.
  bool get canPlay;
  String? get billingAccount;
  bool get gamesRecoveryAvailable;
  Future<bool> linkGames();
  Future<CommandResult> command(
    String type,
    Map<String, Object?> args, {
    String? op,
    bool durable = true,
  });
  Future<String?> startReward(String placement, {String? kind});
  Future<bool> awaitReward(String token);
  Future<ApiResponse> verifyPurchase(String product, String token);
  Future<bool> refreshState();
}

/// Single owner of identity, session, reachability and the retry outbox.
/// Screens never probe the network themselves; they read [phase].
class OnlineService extends ChangeNotifier implements OnlineGateway {
  OnlineService({
    required this.api,
    required this.store,
    required this.packageName,
    required this.expectedEnv,
    required this.timezoneMinutes,
    Future<bool> Function()? internetProbe,
    Future<String?> Function()? gamesCode,
    Future<void> Function(Duration)? pause,
    Random? random,
    this.heartbeatInterval = const Duration(seconds: 15),
    this.failureConfirmation = const Duration(seconds: 4),
    this.outboxRetry = const Duration(seconds: 5),
  }) : _internetProbe = internetProbe,
       _gamesCode = gamesCode,
       _pause = pause ?? Future<void>.delayed,
       _random = random ?? Random.secure();

  final ApiClient api;
  final IdentityStore store;
  final String packageName;
  final String expectedEnv;
  final int Function() timezoneMinutes;
  final Duration heartbeatInterval;
  final Duration failureConfirmation;
  final Duration outboxRetry;
  final Future<bool> Function()? _internetProbe;
  final Future<String?> Function()? _gamesCode;
  final Future<void> Function(Duration) _pause;
  final Random _random;

  /// Called with the full /v1/state body and with each command's wallet view.
  void Function(Map<String, dynamic> state)? onState;
  void Function(Map<String, dynamic> wallet)? onWallet;
  void Function(PendingCommand command, ApiResponse response)? onRejected;

  ConnectionPhase _phase = ConnectionPhase.starting;
  ConnectionPhase get phase => _phase;
  bool _everOnline = false;
  bool get everOnline => _everOnline;
  @override
  bool get canPlay => _phase == ConnectionPhase.online;
  @override
  String? get billingAccount => _billingAccount;
  String? _billingAccount;
  String? get playerId => _identity?.playerId;
  @override
  bool get gamesRecoveryAvailable => _gamesCode != null;

  final Stopwatch _clock = Stopwatch()..start();
  Identity? _identity;
  String? _token;
  int _tokenExpiresAt = 0;
  Future<ApiResponse?>? _refreshing;
  int _failures = 0;
  int _firstFailureAt = 0;
  int _recoveryAttempt = 0;
  bool _foreground = true;
  bool _disposed = false;
  bool _connecting = false;
  Timer? _heartbeat;
  Timer? _recovery;
  Timer? _flushTimer;
  Future<void> _lane = Future<void>.value();
  final _outbox = <PendingCommand>[];
  bool _outboxLoaded = false;
  int _serial = 0;

  void _setPhase(ConnectionPhase value) {
    if (_phase == value || _disposed) return;
    _phase = value;
    if (value == ConnectionPhase.online) _everOnline = true;
    notifyListeners();
  }

  // ---- startup and recovery -------------------------------------------------

  /// Establishes identity, a session and the authoritative state. Safe to
  /// call again (Retry). Never throws.
  Future<void> start() async {
    if (_disposed || _connecting) return;
    if (!api.configured) {
      _setPhase(ConnectionPhase.notConfigured);
      return;
    }
    _connecting = true;
    try {
      if (!_outboxLoaded) {
        _outbox.addAll(await store.readOutbox());
        _outboxLoaded = true;
      }
      await _connect();
    } finally {
      _connecting = false;
    }
  }

  Future<void> _connect() async {
    final config = await api.request('GET', '/v1/config');
    if (!config.ok) {
      await _fail(config);
      return;
    }
    if (config.body['env'] != expectedEnv) {
      _setPhase(ConnectionPhase.notConfigured);
      return;
    }
    _identity ??= await store.read();
    final problem = _identity == null
        ? await _register()
        : await _ensureSession();
    if (problem != null) {
      await _fail(problem);
      return;
    }
    // Deliver anything saved while offline first, so the state we restore
    // already includes it.
    await _serialize(() => _flushOutbox(force: true));
    if (!await refreshState()) {
      await _fail(
        const ApiResponse(0, {}, failure: ApiFailure.backendUnavailable),
      );
      return;
    }
    _failures = 0;
    _recoveryAttempt = 0;
    _recovery?.cancel();
    _setPhase(ConnectionPhase.online);
    _startHeartbeat();
    await command('timezone.set', {'tz': timezoneMinutes()});
  }

  Future<ApiResponse?> _register() async {
    final challenge = await api.request('GET', '/v1/auth/challenge');
    if (!challenge.ok) return challenge;
    if (challenge.body['required'] == true) {
      // Play Integrity is enforced by the server; this build cannot attest.
      return const ApiResponse(403, {
        'error': 'attestation_failed',
      }, failure: ApiFailure.rejected);
    }
    final created = await api.request(
      'POST',
      '/v1/auth/register',
      body: {'pkg': packageName, 'tz': timezoneMinutes()},
    );
    if (!created.ok) return created;
    return _adopt(created);
  }

  Future<ApiResponse?> _adopt(ApiResponse response) async {
    final player = response.body['playerId'];
    final refresh = response.body['refresh'];
    final session = response.body['session'];
    if (player is! String || refresh is! String || session is! Map) {
      return const ApiResponse(0, {}, failure: ApiFailure.backendUnavailable);
    }
    _identity = Identity(player, refresh);
    await store.write(_identity!);
    _acceptSession(
      Map<String, dynamic>.from(session),
      response.body['serverNow'],
    );
    return null;
  }

  void _acceptSession(Map<String, dynamic> session, Object? serverNow) {
    final token = session['token'];
    final expiresAt = session['expiresAt'];
    if (token is! String || expiresAt is! int || serverNow is! int) return;
    _token = token;
    _tokenExpiresAt = _clock.elapsedMilliseconds + (expiresAt - serverNow);
  }

  bool get _tokenFresh =>
      _token != null && _clock.elapsedMilliseconds < _tokenExpiresAt - 60000;

  /// Returns null when a usable session exists, otherwise the failing response.
  Future<ApiResponse?> _ensureSession() {
    if (_tokenFresh) return Future<ApiResponse?>.value(null);
    return _refreshing ??= _refreshSession().whenComplete(() {
      _refreshing = null;
    });
  }

  Future<ApiResponse?> _refreshSession() async {
    final identity = _identity;
    if (identity == null) {
      return const ApiResponse(401, {}, failure: ApiFailure.unauthorized);
    }
    final response = await api.request(
      'POST',
      '/v1/auth/refresh',
      body: {'refresh': identity.refresh},
    );
    if (response.ok) {
      final refresh = response.body['refresh'];
      final session = response.body['session'];
      if (refresh is String && session is Map) {
        _identity = Identity(identity.playerId, refresh);
        await store.write(_identity!);
        _acceptSession(
          Map<String, dynamic>.from(session),
          response.body['serverNow'],
        );
        return null;
      }
      return const ApiResponse(0, {}, failure: ApiFailure.backendUnavailable);
    }
    if (response.failure == ApiFailure.unauthorized) {
      _token = null;
      _setPhase(ConnectionPhase.sessionExpired);
    }
    return response;
  }

  Future<void> _fail(ApiResponse response) async {
    _heartbeat?.cancel();
    switch (response.failure) {
      case ApiFailure.updateRequired:
        _setPhase(ConnectionPhase.updateRequired);
        return;
      case ApiFailure.unauthorized:
        _setPhase(ConnectionPhase.sessionExpired);
        return;
      case ApiFailure.rejected:
        _setPhase(
          response.status == 403
              ? ConnectionPhase.authFailed
              : ConnectionPhase.backendUnavailable,
        );
        _scheduleRecovery();
        return;
      case ApiFailure.none:
      case ApiFailure.noInternet:
      case ApiFailure.backendUnavailable:
        _setPhase(await _classify());
        _scheduleRecovery();
    }
  }

  Future<ConnectionPhase> _classify() async {
    // Wi-Fi or mobile data alone proves nothing, so we look for any internet
    // reachability only to tell "no internet" from "our backend is down".
    final reachable =
        await (_internetProbe?.call() ?? Future<bool>.value(false));
    return reachable
        ? ConnectionPhase.backendUnavailable
        : ConnectionPhase.noInternet;
  }

  Duration _backoff() {
    const steps = [2, 4, 8, 16, 30];
    final seconds = steps[min(_recoveryAttempt, steps.length - 1)];
    return Duration(milliseconds: seconds * 1000 + _random.nextInt(1000));
  }

  void _scheduleRecovery() {
    if (_disposed) return;
    _recovery?.cancel();
    _recovery = Timer(_backoff(), () {
      _recoveryAttempt++;
      unawaited(start());
    });
  }

  /// Runs one reachability check, as the periodic heartbeat does.
  @visibleForTesting
  Future<void> checkNow() => _beat();

  /// Retry button.
  Future<void> retryNow() async {
    _recovery?.cancel();
    _recoveryAttempt = 0;
    if (_phase == ConnectionPhase.sessionExpired) {
      _token = null;
    }
    await start();
  }

  /// After a revoked session: restore the linked Play Games profile.
  Future<bool> restoreWithGames() async {
    final code = await _gamesCode?.call();
    if (code == null) return false;
    final response = await api.request(
      'POST',
      '/v1/auth/recover',
      body: {'pkg': packageName, 'code': code},
    );
    if (!response.ok || await _adopt(response) != null) return false;
    await start();
    return canPlay;
  }

  /// After a revoked session with no recoverable profile.
  Future<void> startNewProfile() async {
    await store.clear();
    _outbox.clear();
    _identity = null;
    _token = null;
    await start();
  }

  /// Links the current profile to the signed-in Play Games account so it can
  /// be recovered on another device.
  @override
  Future<bool> linkGames() async {
    final code = await _gamesCode?.call();
    if (code == null) return false;
    final response = await _authed(
      'POST',
      '/v1/auth/link',
      body: {'code': code},
    );
    return response.ok;
  }

  // ---- reachability while playing ---------------------------------------------

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (foreground && canPlay) unawaited(_beat());
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => unawaited(_beat()));
  }

  Future<void> _beat() async {
    if (_disposed || !_foreground || !canPlay) return;
    final response = await api.request('GET', '/v1/ping');
    if (_observe(response)) return _interrupt();
    if (_failures > 0 && canPlay) {
      // Re-check quickly so a real outage is confirmed without a long wait.
      _heartbeat?.cancel();
      await _pause(failureConfirmation);
      if (_disposed) return;
      _startHeartbeat();
      final again = await api.request('GET', '/v1/ping');
      if (_observe(again)) await _interrupt();
    }
  }

  /// Brief fluctuations do not interrupt play. Two failures at least
  /// [failureConfirmation] apart do. Returns true when play must pause.
  bool _observe(ApiResponse response) {
    if (_disposed) return false;
    if (response.failure == ApiFailure.updateRequired) {
      _heartbeat?.cancel();
      _setPhase(ConnectionPhase.updateRequired);
      return false;
    }
    if (response.ok || (!response.retryable && response.status != 401)) {
      _failures = 0;
      return false;
    }
    if (response.status == 401) return false;
    final now = _clock.elapsedMilliseconds;
    if (_failures == 0) _firstFailureAt = now;
    _failures++;
    return _failures >= 2 &&
        now - _firstFailureAt >= failureConfirmation.inMilliseconds &&
        _phase == ConnectionPhase.online;
  }

  Future<void> _interrupt() async {
    _heartbeat?.cancel();
    _setPhase(await _classify());
    _recoveryAttempt = 0;
    _scheduleRecovery();
  }

  // ---- authenticated requests ---------------------------------------------------

  Future<ApiResponse> _authed(
    String method,
    String path, {
    Object? body,
  }) async {
    final problem = await _ensureSession();
    if (problem != null) {
      if (_observe(problem)) unawaited(_interrupt());
      return problem;
    }
    var response = await api.request(method, path, body: body, token: _token);
    if (response.failure == ApiFailure.unauthorized) {
      _token = null;
      final retry = await _ensureSession();
      if (retry != null) return retry;
      response = await api.request(method, path, body: body, token: _token);
    }
    if (_observe(response)) unawaited(_interrupt());
    return response;
  }

  void _applyWallet(Object? wallet) {
    if (wallet is! Map) return;
    final map = Map<String, dynamic>.from(wallet);
    if (map['billingAccount'] is String) {
      _billingAccount = map['billingAccount'] as String;
    }
    onWallet?.call(map);
  }

  @override
  Future<bool> refreshState() async {
    final response = await _authed('GET', '/v1/state');
    if (!response.ok) return false;
    final wallet = response.body['wallet'];
    if (wallet is Map && wallet['billingAccount'] is String) {
      _billingAccount = wallet['billingAccount'] as String;
    }
    onState?.call(response.body);
    return true;
  }

  // ---- commands and the outbox ---------------------------------------------------

  String _newOp() {
    final bytes = List.generate(9, (_) => _random.nextInt(256));
    final text = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'c-${_serial++}-$text';
  }

  Future<T> _serialize<T>(Future<T> Function() task) {
    final result = _lane.then((_) => task());
    _lane = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<CommandResult> command(
    String type,
    Map<String, Object?> args, {
    String? op,
    bool durable = true,
  }) {
    final pending = PendingCommand(op ?? _newOp(), type, args);
    return _serialize(() => _deliver(pending, durable));
  }

  Future<CommandResult> _deliver(PendingCommand command, bool durable) async {
    if (!_outboxLoaded) {
      _outbox.addAll(await store.readOutbox());
      _outboxLoaded = true;
    }
    if (canPlay && _outbox.isNotEmpty) await _flushOutbox();
    if (_outbox.isNotEmpty || !canPlay) {
      // Snapshots such as a saved route are superseded by the next one.
      if (!durable) return CommandResult.pending;
      await _enqueue(command);
      _scheduleFlush();
      return CommandResult.pending;
    }
    final response = await _post(command);
    if (response.ok) {
      _applyWallet(response.body['wallet']);
      return CommandResult(
        ok: true,
        status: response.status,
        body: response.body,
      );
    }
    if (response.retryable || response.failure == ApiFailure.unauthorized) {
      if (!durable) return CommandResult.pending;
      await _enqueue(command);
      _scheduleFlush();
      return CommandResult.pending;
    }
    onRejected?.call(command, response);
    return CommandResult(
      ok: false,
      status: response.status,
      error: response.error,
      body: response.body,
    );
  }

  Future<ApiResponse> _post(PendingCommand command) => _authed(
    'POST',
    '/v1/command',
    body: {'op': command.op, 'type': command.type, 'args': command.args},
  );

  Future<void> _enqueue(PendingCommand command) async {
    if (_outbox.any((entry) => entry.op == command.op)) return;
    _outbox.add(command);
    await store.writeOutbox(_outbox);
  }

  void _scheduleFlush() {
    if (_disposed || _flushTimer?.isActive == true) return;
    _flushTimer = Timer(outboxRetry, () {
      _flushTimer = null;
      if (canPlay) unawaited(_serialize(() => _flushOutbox()));
    });
  }

  /// Delivers saved commands in order. Server-side idempotency makes a
  /// repeat after a lost response harmless.
  Future<void> _flushOutbox({bool force = false}) async {
    while (_outbox.isNotEmpty && (force || canPlay)) {
      final command = _outbox.first;
      final response = await _post(command);
      if (response.ok) {
        _applyWallet(response.body['wallet']);
      } else if (response.retryable ||
          response.failure == ApiFailure.unauthorized) {
        return;
      } else {
        onRejected?.call(command, response);
      }
      _outbox.removeAt(0);
      await store.writeOutbox(_outbox);
    }
  }

  int get pendingCommands => _outbox.length;

  // ---- rewards and purchases ----------------------------------------------------

  @override
  Future<String?> startReward(String placement, {String? kind}) async {
    if (!canPlay) return null;
    final response = await _authed(
      'POST',
      '/v1/rewards/start/$placement',
      body: {if (kind != null) 'kind': kind},
    );
    final token = response.body['token'];
    return response.ok && token is String ? token : null;
  }

  /// Waits for Google's signed callback to reach the server.
  @override
  Future<bool> awaitReward(String token) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final response = await _authed('GET', '/v1/rewards/status/$token');
      if (response.ok && response.body['verified'] == true) return true;
      if (!response.ok && !response.retryable) return false;
      await _pause(const Duration(milliseconds: 1500));
    }
    return false;
  }

  @override
  Future<ApiResponse> verifyPurchase(String product, String token) async {
    final response = await _authed(
      'POST',
      '/v1/play/verify',
      body: {'product': product, 'token': token},
    );
    if (response.ok) _applyWallet(response.body['wallet']);
    return response;
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    _recovery?.cancel();
    _flushTimer?.cancel();
    super.dispose();
  }
}
