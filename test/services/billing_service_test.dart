import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pathwise/logic/billing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('billing outcomes are fail closed and finalize after verification and durable save', () async {
    final calls = <String>[];
    Future<BillingOutcome> process(
      PurchaseStatus status, {
      bool verified = true,
      bool saved = true,
    }) => processPurchase(
      status: status,
      verify: () async {
        calls.add('verify');
        return verified ? (id: 'grant', product: themePassProduct) : null;
      },
      persist: (_) async {
        calls.add('persist');
        return saved;
      },
      finalize: () async {
        calls.add('finalize');
      },
    );

    expect(await process(PurchaseStatus.pending), BillingOutcome.pending);
    expect(await process(PurchaseStatus.canceled), BillingOutcome.canceled);
    expect(await process(PurchaseStatus.error), BillingOutcome.rejected);
    expect(calls, isEmpty);
    expect(
      await process(PurchaseStatus.purchased, verified: false),
      BillingOutcome.rejected,
    );
    expect(calls, ['verify']);
    calls.clear();
    expect(
      await process(PurchaseStatus.purchased, saved: false),
      BillingOutcome.retry,
    );
    expect(calls, ['verify', 'persist']);
    calls.clear();
    expect(await process(PurchaseStatus.restored), BillingOutcome.complete);
    expect(calls, ['verify', 'persist', 'finalize']);
  });
}
