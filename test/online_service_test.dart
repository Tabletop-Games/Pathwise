import 'package:flutter_test/flutter_test.dart';

import '../lib/online/api_client.dart';
import '../lib/online/identity_store.dart';
import '../lib/online/online_service.dart';
import 'support/fake_backend.dart';

OnlineService service(
  FakeBackend backend, {
  IdentityStore? store,
  int build = 9,
  String env = 'development',
}) => OnlineService(
  api: ApiClient(
    baseUrl: 'https://api.example.test',
    transport: backend,
    build: build,
  ),
  store: store ?? IdentityStore(MemoryKeyValueStore()),
  packageName: 'com.shenmareparas.pathwise.debug',
  expectedEnv: env,
  timezoneMinutes: () => 0,
  internetProbe: () async =>
      (await backend.send(
        'GET',
        Uri.parse('https://www.gstatic.com/generate_204'),
        headers: const {},
        timeout: const Duration(seconds: 1),
      )).status ==
      204,
  pause: (_) async {},
  failureConfirmation: Duration.zero,
);

void main() {
  test('startup registers once and reaches online', () async {
    final backend = FakeBackend();
    final store = IdentityStore(MemoryKeyValueStore());
    Map<String, dynamic>? state;
    final online = service(backend, store: store)
      ..onState = (value) => state = value;
    await online.start();
    expect(online.phase, ConnectionPhase.online);
    expect(online.canPlay, isTrue);
    expect(backend.registrations, 1);
    expect(state?['wallet']['coins'], 50);
    expect(online.billingAccount, 'a' * 64);
    expect((await store.read())?.playerId, 'p_test1');
    online.dispose();

    // A restart reuses the stored identity instead of creating a new player.
    final again = service(backend, store: store);
    await again.start();
    expect(again.canPlay, isTrue);
    expect(backend.registrations, 1);
    expect(backend.requests, contains('POST /v1/auth/refresh'));
    again.dispose();
  });

  test('offline startup tells no internet from an outage', () async {
    final backend = FakeBackend()
      ..offline = true
      ..internet = false;
    final online = service(backend);
    await online.start();
    expect(online.phase, ConnectionPhase.noInternet);
    expect(online.canPlay, isFalse);

    backend
      ..offline = false
      ..internet = true
      ..down = true;
    await online.retryNow();
    expect(online.phase, ConnectionPhase.backendUnavailable);

    backend.down = false;
    await online.retryNow();
    expect(online.phase, ConnectionPhase.online);
    online.dispose();
  });

  test('a required update or wrong environment blocks play', () async {
    final backend = FakeBackend()..minBuild = 10;
    final old = service(backend, build: 9);
    await old.start();
    expect(old.phase, ConnectionPhase.updateRequired);
    old.dispose();

    final debugBuild = service(FakeBackend()..env = 'production');
    await debugBuild.start();
    expect(debugBuild.phase, ConnectionPhase.notConfigured);
    expect(debugBuild.canPlay, isFalse);
    debugBuild.dispose();

    final unconfigured = OnlineService(
      api: ApiClient(baseUrl: '', transport: FakeBackend(), build: 1),
      store: IdentityStore(MemoryKeyValueStore()),
      packageName: 'com.shenmareparas.pathwise',
      expectedEnv: 'production',
      timezoneMinutes: () => 0,
    );
    await unconfigured.start();
    expect(unconfigured.phase, ConnectionPhase.notConfigured);
    unconfigured.dispose();
  });

  test('required attestation reports an auth failure', () async {
    final online = service(FakeBackend()..requireAttestation = true);
    await online.start();
    expect(online.phase, ConnectionPhase.authFailed);
    online.dispose();
  });

  test('expired sessions renew; revoked devices sign in again', () async {
    final backend = FakeBackend()..tokenTtlMs = 30000; // inside the 60 s margin
    final online = service(backend);
    await online.start();
    final before = backend.sessions;
    await online.command('tutorial.ack', {'id': 'walls'});
    expect(
      backend.sessions,
      greaterThan(before),
      reason: 'refreshed before use',
    );

    backend
      ..revokedTokens.add('token-${backend.sessions}')
      ..refreshRevoked = true;
    await online.refreshState();
    expect(online.phase, ConnectionPhase.sessionExpired);
    expect(online.canPlay, isFalse);
    online.dispose();
  });

  test('one failed heartbeat does not interrupt play', () async {
    final backend = FakeBackend();
    final online = service(backend);
    await online.start();
    var interrupted = 0;
    online.addListener(() {
      if (!online.canPlay) interrupted++;
    });
    // One dropped request followed by a success: no interruption.
    backend.down = true;
    final blip = online.checkNow();
    backend.down = false;
    await blip;
    expect(online.canPlay, isTrue);

    backend.down = true;
    await online.checkNow();
    expect(online.canPlay, isFalse);
    expect(online.phase, ConnectionPhase.backendUnavailable);
    expect(interrupted, greaterThan(0));

    backend.down = false;
    await online.retryNow();
    expect(online.canPlay, isTrue);
    online.dispose();
  });

  test('offline commands are kept and delivered once', () async {
    final backend = FakeBackend();
    final store = IdentityStore(MemoryKeyValueStore());
    final online = service(backend, store: store);
    await online.start();
    backend.failNextCommands = 1;
    final first = await online.command('hint.use', {'attempt': 'levels/1'});
    expect(first.queued, isTrue);
    expect(online.pendingCommands, 1);
    expect((await store.readOutbox()).single.type, 'hint.use');

    // The app is killed and restarted before reconnecting.
    online.dispose();
    final restarted = service(backend, store: store);
    await restarted.start();
    expect(restarted.pendingCommands, 0);
    final hints = backend.executed.where((c) => c['type'] == 'hint.use');
    expect(hints.length, 1);
    restarted.dispose();
  });

  test('retrying one operation id never applies it twice', () async {
    final backend = FakeBackend();
    final online = service(backend);
    await online.start();
    await online.command('hint.buy', const {}, op: 'op-buy-0001');
    final replay = await online.command(
      'hint.buy',
      const {},
      op: 'op-buy-0001',
    );
    expect(replay.ok, isTrue);
    expect(replay.body['replayed'], isTrue);
    expect(backend.executed.where((c) => c['type'] == 'hint.buy').length, 1);
    online.dispose();
  });

  test('a rejected command is reported and not retried', () async {
    final backend = FakeBackend()..rejected['play.complete'] = 422;
    final online = service(backend);
    final rejections = <String>[];
    online.onRejected = (command, response) => rejections.add(command.type);
    await online.start();
    final result = await online.command('play.complete', {'key': 'levels/1'});
    expect(result.ok, isFalse);
    expect(result.queued, isFalse);
    expect(result.error, 'invalid_route');
    expect(rejections, ['play.complete']);
    expect(online.pendingCommands, 0);
    online.dispose();
  });

  test('snapshot commands are not queued while offline', () async {
    final backend = FakeBackend();
    final online = service(backend);
    await online.start();
    backend.failNextCommands = 1;
    final save = await online.command('attempt.save', {
      'key': 'levels/1',
    }, durable: false);
    expect(save.queued, isTrue);
    expect(online.pendingCommands, 0);
    online.dispose();
  });

  test('rewards wait for a verified callback', () async {
    final backend = FakeBackend()..verifiedAfterPolls = 3;
    final online = service(backend);
    await online.start();
    final token = await online.startReward('coins');
    expect(token, 'f' * 64);
    expect(await online.awaitReward(token!), isTrue);
    expect(backend.rewardPolls, 3);

    backend
      ..rewardVerified = false
      ..rewardPolls = 0;
    expect(await online.awaitReward(token), isFalse);
    online.dispose();
  });

  test('no reward session is requested while offline', () async {
    final backend = FakeBackend()
      ..offline = true
      ..internet = false;
    final online = service(backend);
    await online.start();
    expect(await online.startReward('coins'), isNull);
    online.dispose();
  });
}
