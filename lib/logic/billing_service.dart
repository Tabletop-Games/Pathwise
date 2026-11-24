import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../model/product_catalog.dart';
import '../online/online_service.dart';
export '../model/product_catalog.dart';

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
  BillingService({required this.persist, this.gateway});

  final Future<bool> Function(VerifiedGrant) persist;

  /// When present, Google Play purchases are verified and credited by the
  /// server, which also acknowledges or consumes them. Without it (unit tests)
  /// the legacy on-device signature check applies.
  final OnlineGateway? gateway;
  static const _commerce = MethodChannel('games.tabletop.pathwise/commerce');
  static const _playKey = String.fromEnvironment(
    'PATHWISE_PLAY_BILLING_PUBLIC_KEY',
  );
  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  String get _storeName => _android ? 'Google Play' : 'the App Store';
  final _retry = <String, PurchaseDetails>{};
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void> _queue = Future.value();
  bool _disposed = false;
  bool _buying = false;
  final products = <ProductDetails>[];
  String? message;

  bool get enabled =>
      const bool.fromEnvironment('PATHWISE_BILLING_ENABLED') &&
      (gateway != null
          // Server verification covers Google Play. App Store receipts have no
          // server verifier yet, so iOS purchases stay off.
          ? _android
          : ((_android && _playKey.isNotEmpty) ||
                defaultTargetPlatform == TargetPlatform.iOS));
  bool get buying => _buying;

  Future<void> start() async {
    if (!enabled || _subscription != null || _disposed) return;
    final store = InAppPurchase.instance;
    _subscription = store.purchaseStream.listen(
      _receive,
      onError: (Object _) {
        _buying = false;
        _report('$_storeName is temporarily unavailable.');
      },
    );
    await refreshCatalog();
    if (!_disposed && products.isNotEmpty) {
      try {
        await store.restorePurchases();
      } catch (_) {
        _report(
          'Purchase recovery is temporarily unavailable. You can retry from the store.',
        );
      }
    }
  }

  Future<void> refreshCatalog() async {
    if (!enabled || _disposed) return;
    try {
      final store = InAppPurchase.instance;
      if (!await store.isAvailable()) {
        _report('$_storeName is unavailable on this device.');
        return;
      }
      final response = await store.queryProductDetails(
        storeProducts.entries
            .where((e) => !e.value.legacy)
            .map((e) => e.key)
            .toSet(),
      );
      if (_disposed) return;
      products
        ..clear()
        ..addAll(response.productDetails);
      _report(response.error == null ? null : 'Some products are unavailable.');
    } catch (_) {
      _report('The store catalog could not be loaded.');
    }
  }

  Future<void> buy(ProductDetails product) async {
    if (!enabled || buying || !products.contains(product)) return;
    final account = gateway?.billingAccount;
    if (gateway != null && (account == null || !gateway!.canPlay)) {
      _report('Connect to the internet to buy.');
      return;
    }
    _buying = true;
    _report('Opening $_storeName…');
    try {
      // The obfuscated account id binds the purchase to this player. The
      // server refuses a purchase made for anyone else.
      final param = PurchaseParam(
        productDetails: product,
        applicationUserName: account,
      );
      final store = InAppPurchase.instance;
      final sent = !consumable(product.id)
          ? await store.buyNonConsumable(purchaseParam: param)
          : await store.buyConsumable(
              purchaseParam: param,
              autoConsume: !_android,
            );
      if (!sent) throw StateError('Purchase sheet unavailable');
    } catch (_) {
      _buying = false;
      _report('The purchase could not be started.');
    }
  }

  Future<void> restore() async {
    if (!enabled || _disposed || buying) return;
    _report('Checking purchases with $_storeName…');
    try {
      for (final purchase in _retry.values.toList()) {
        _receive([purchase]);
      }
      await InAppPurchase.instance.restorePurchases();
      if (message == 'Checking purchases with $_storeName…') {
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
    final token = _android
        ? purchase.verificationData.serverVerificationData
        : (purchase.purchaseID ?? '');
    final outcome = await processPurchase(
      status: purchase.status,
      verify: () => _verify(purchase, token),
      persist: persist,
      finalize: () async {
        final store = InAppPurchase.instance;
        if (_android && consumable(purchase.productID)) {
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
      BillingOutcome.pending => 'Payment is pending in $_storeName.',
      BillingOutcome.canceled => 'Purchase canceled.',
      BillingOutcome.rejected => 'The store could not verify this purchase.',
      BillingOutcome.retry => 'Purchase is awaiting verification or delivery. Use Restore purchases to retry.',
      BillingOutcome.complete => 'Verified purchase applied.',
    });
  }

  Future<VerifiedGrant?> _verify(PurchaseDetails purchase, String token) async {
    if (_disposed || token.isEmpty) return null;
    final product = purchase.productID;
    final server = gateway;
    if (server != null) return _verifyOnServer(server, purchase, token);
    const package = 'com.shenmareparas.pathwise';
    final bool? valid;
    if (_android && purchase is GooglePlayPurchaseDetails) {
      final data = purchase.billingClientPurchase;
      if (data.purchaseState != PurchaseStateWrapper.purchased ||
          data.packageName != package ||
          data.purchaseToken != token ||
          data.products.length != 1 ||
          data.products.single != product) {
        return null;
      }
      valid = await _commerce
          .invokeMethod<bool>('verifyPlayPurchase', {
            'key': _playKey,
            'data': data.originalJson,
            'signature': data.signature,
          })
          .timeout(const Duration(seconds: 5));
    } else if (!_android) {
      valid = await _commerce
          .invokeMethod<bool>('verifyStoreKitPurchase', {
            'transaction': token,
            'product': product,
          })
          .timeout(const Duration(seconds: 30));
    } else {
      return null;
    }
    if (valid != true) return null;
    // Keep the Android key identical to the retired verifier's ledger key.
    final identity = _android
        ? '$package\u0000$token'
        : 'storekit/$package/$token';
    return (
      id: sha256.convert(utf8.encode(identity)).toString(),
      product: product,
    );
  }

  Future<VerifiedGrant?> _verifyOnServer(
    OnlineGateway server,
    PurchaseDetails purchase,
    String token,
  ) async {
    final product = purchase.productID;
    if (!_android || purchase is! GooglePlayPurchaseDetails) return null;
    final data = purchase.billingClientPurchase;
    if (data.purchaseState != PurchaseStateWrapper.purchased ||
        data.purchaseToken != token ||
        data.products.length != 1 ||
        data.products.single != product) {
      return null;
    }
    final response = await server.verifyPurchase(product, token);
    if (response.ok && response.body['id'] is String) {
      return (id: response.body['id'] as String, product: product);
    }
    // Network trouble, rate limits and "still pending" are retried later; a
    // definite refusal is final.
    if (response.retryable ||
        response.error == 'payment_pending' ||
        response.status == 401) {
      throw StateError('Purchase verification will be retried');
    }
    return null;
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
