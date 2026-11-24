import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../model/product_catalog.dart';
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
  BillingService({
    required this.persist,
    this.canPurchase,
    this.readyForConsumable,
    this.beforeConsume,
    this.onOwnedProducts,
  });

  final Future<bool> Function(VerifiedGrant) persist;

  /// Every purchase needs an internet connection.
  final bool Function()? canPurchase;

  /// Real-money coin packs need a recoverable account and a successful cloud
  /// save. Returns false to block the purchase before the store opens.
  final Future<bool> Function()? readyForConsumable;

  /// Called after the grant is saved and before a coin pack is consumed. It
  /// attempts a cloud sync. Failure must not block consumption, because the
  /// grant is already durable on the device and the sync retries later.
  final Future<void> Function()? beforeConsume;

  /// Receives the permanent products Google Play reports as owned.
  final void Function(Set<String> owned)? onOwnedProducts;
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
      ((_android && _playKey.isNotEmpty) ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get buying => _buying;

  Future<void> start() async {
    if (!enabled || _subscription != null || _disposed) return;
    unawaited(reconcileEntitlements());
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

  /// Reconciles permanent entitlements against Google Play ownership. A refund
  /// removes an entitlement here even when the cloud save still shows it.
  Future<void> reconcileEntitlements() async {
    final report = onOwnedProducts;
    if (!enabled || !_android || _disposed || report == null) return;
    try {
      final addition = InAppPurchase.instance
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await addition.queryPastPurchases();
      if (response.error != null) return;
      final owned = <String>{
        for (final purchase in response.pastPurchases)
          if ((purchase.status == PurchaseStatus.purchased ||
                  purchase.status == PurchaseStatus.restored) &&
              !consumable(purchase.productID))
            purchase.productID,
      };
      report(owned);
    } catch (_) {
      // Keep the current entitlements when Play cannot answer.
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
    if (canPurchase != null && !canPurchase!()) {
      _report('Connect to the internet to buy.');
      return;
    }
    if (consumable(product.id) && readyForConsumable != null) {
      final ready = await readyForConsumable!();
      if (!ready) {
        _report(
          'Sign in to Google Play Games and sync your progress before buying coins. Your purchases are then protected.',
        );
        return;
      }
    }
    _buying = true;
    _report('Opening $_storeName…');
    try {
      final param = PurchaseParam(productDetails: product);
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
          try {
            await beforeConsume?.call();
          } catch (_) {
            // Sync is retried later. The local grant is already saved.
          }
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
