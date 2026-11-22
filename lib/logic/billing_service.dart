import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

const themePassProduct = 'pathwise_themes_forever';

const storeProducts = {
  'pathwise_coins_120': (label: '120 coins', coins: 120),
  'pathwise_coins_340': (label: '340 coins', coins: 340),
  'pathwise_coins_800': (label: '800 coins', coins: 800),
  themePassProduct: (label: 'All themes forever', coins: 0),
};

typedef VerifiedGrant = ({String id, String product});

enum BillingOutcome { pending, canceled, rejected, retry, complete }

/// No acknowledgement or consumption can occur ahead of a durable verified grant.
Future<BillingOutcome> processPurchase({
  required PurchaseStatus status,
  required Future<VerifiedGrant?> Function() verify,
  required Future<bool> Function(VerifiedGrant) persist,
  required Future<void> Function() finalize,
}) async {
  switch (status) {
    case PurchaseStatus.pending:
      return BillingOutcome.pending;
    case PurchaseStatus.canceled:
      return BillingOutcome.canceled;
    case PurchaseStatus.error:
      return BillingOutcome.rejected;
    case PurchaseStatus.purchased:
    case PurchaseStatus.restored:
      try {
        final grant = await verify();
        if (grant == null) return BillingOutcome.rejected;
        if (!await persist(grant)) return BillingOutcome.retry;
        await finalize();
        return BillingOutcome.complete;
      } catch (_) {
        return BillingOutcome.retry;
      }
  }
}

class BillingService extends ChangeNotifier {
  BillingService({required this.profile, required this.persist});

  final Future<String?> Function() profile;
  final Future<bool> Function(VerifiedGrant) persist;
  final _endpoint = Uri.tryParse(
    const String.fromEnvironment('PATHWISE_BILLING_VERIFY_URL'),
  );
  final _retry = <String, PurchaseDetails>{};
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void> _queue = Future.value();
  bool _disposed = false;
  bool _buying = false;
  final products = <ProductDetails>[];
  String? message;

  bool get enabled =>
      defaultTargetPlatform == TargetPlatform.android &&
      const bool.fromEnvironment('PATHWISE_BILLING_ENABLED') &&
      _endpoint?.scheme == 'https' &&
      _endpoint!.hasAuthority &&
      _endpoint.userInfo.isEmpty &&
      _endpoint.path == '/v1/play/verify' &&
      !_endpoint.hasQuery &&
      !_endpoint.hasFragment;
  bool get buying => _buying;

  Future<void> start() async {
    if (!enabled || _subscription != null || _disposed) return;
    final store = InAppPurchase.instance;
    _subscription = store.purchaseStream.listen(
      _receive,
      onError: (Object _) {
        _buying = false;
        _report('Google Play is temporarily unavailable.');
      },
    );
    await refreshCatalog();
  }

  Future<void> refreshCatalog() async {
    if (!enabled || _disposed) return;
    try {
      if (!await _verifierReady()) {
        products.clear();
        _report('Purchase verification is unavailable. Try again later.');
        return;
      }
      final store = InAppPurchase.instance;
      if (!await store.isAvailable()) {
        _report('Google Play is unavailable on this device.');
        return;
      }
      final response = await store.queryProductDetails(
        storeProducts.keys.toSet(),
      );
      if (_disposed) return;
      products
        ..clear()
        ..addAll(response.productDetails);
      _report(response.error == null ? null : 'Some products are unavailable.');
    } catch (_) {
      _report('The Google Play catalog could not be loaded.');
    }
  }

  Future<void> buy(ProductDetails product) async {
    if (!enabled || buying || !products.contains(product)) return;
    _buying = true;
    _report('Opening Google Play…');
    try {
      if (!await _verifierReady()) throw StateError('Verification unavailable');
      final secret = await profile();
      if (secret == null || _disposed) throw StateError('Profile unavailable');
      final param = GooglePlayPurchaseParam(
        productDetails: product,
        applicationUserName: sha256.convert(utf8.encode(secret)).toString(),
      );
      final store = InAppPurchase.instance;
      final sent = product.id == themePassProduct
          ? await store.buyNonConsumable(purchaseParam: param)
          : await store.buyConsumable(purchaseParam: param, autoConsume: false);
      if (!sent) throw StateError('Purchase sheet unavailable');
    } catch (_) {
      _buying = false;
      _report('The purchase could not be started.');
    }
  }

  Future<void> restore() async {
    if (!enabled || _disposed || buying) return;
    _report('Checking purchases with Google Play…');
    try {
      for (final purchase in _retry.values.toList()) {
        _receive([purchase]);
      }
      await InAppPurchase.instance.restorePurchases();
      if (message == 'Checking purchases with Google Play…') {
        _report('Restore requested. Verified purchases will appear here.');
      }
    } catch (_) {
      _report('Restoration is temporarily unavailable.');
    }
  }

  void _receive(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      _queue = _queue.then((_) => _handle(purchase));
    }
  }

  Future<void> _handle(PurchaseDetails purchase) async {
    if (_disposed || !storeProducts.containsKey(purchase.productID)) return;
    final token = purchase.verificationData.serverVerificationData;
    final outcome = await processPurchase(
      status: purchase.status,
      verify: () => _verify(purchase.productID, token),
      persist: persist,
      finalize: () async {
        final store = InAppPurchase.instance;
        if (purchase.productID != themePassProduct) {
          final result = await store
              .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
              .consumePurchase(purchase);
          if (result.responseCode != BillingResponse.ok &&
              result.responseCode != BillingResponse.itemNotOwned) {
            throw StateError('Google Play could not consume the purchase');
          }
        } else if (purchase.pendingCompletePurchase) {
          await store.completePurchase(purchase);
        }
      },
    );
    _buying = false;
    if (outcome == BillingOutcome.retry && token.isNotEmpty) {
      _retry[token] = purchase;
    } else {
      _retry.remove(token);
    }
    _report(switch (outcome) {
      BillingOutcome.pending => 'Payment is pending in Google Play.',
      BillingOutcome.canceled => 'Purchase canceled.',
      BillingOutcome.rejected => 'Google Play could not verify this purchase.',
      BillingOutcome.retry => 'Purchase is awaiting verification or delivery. Use Restore purchases to retry.',
      BillingOutcome.complete => 'Verified purchase applied.',
    });
  }

  Future<bool> _verifierReady() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(_endpoint!.replace(path: '/healthz'));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != 200) return false;
      final data = jsonDecode(
        await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 5)),
      );
      return data is Map &&
          data['status'] == 'ready' &&
          data['package'] == 'games.tabletop.pathwise';
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<VerifiedGrant?> _verify(String product, String token) async {
    final secret = await profile();
    if (secret == null || token.isEmpty || _disposed)
      throw StateError('Verification unavailable');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(_endpoint!);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      request.write(jsonEncode({'product': product, 'token': token}));
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode == 403 || response.statusCode == 422) return null;
      if (response.statusCode != 200)
        throw StateError('Verification service unavailable');
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(body);
      if (data is! Map ||
          data['product'] != product ||
          data['id'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['id'] as String)) {
        return null;
      }
      return (id: data['id'] as String, product: product);
    } finally {
      client.close(force: true);
    }
  }

  void _report(String? value) {
    if (_disposed) return;
    message = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
