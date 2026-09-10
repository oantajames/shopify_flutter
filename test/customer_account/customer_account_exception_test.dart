import 'package:flutter_test/flutter_test.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_exception.dart';

void main() {
  /// Every failure and whether the UI must stay silent for it. A new enum
  /// value has to be added here on purpose.
  const expected = <ShopifyCustomerAccountFailure, bool>{
    ShopifyCustomerAccountFailure.cancelled: true,
    ShopifyCustomerAccountFailure.timeout: true,
    ShopifyCustomerAccountFailure.browserUnavailable: false,
    ShopifyCustomerAccountFailure.stateMismatch: false,
    ShopifyCustomerAccountFailure.exchangeFailed: false,
    ShopifyCustomerAccountFailure.refreshFailed: false,
    ShopifyCustomerAccountFailure.network: false,
    ShopifyCustomerAccountFailure.notConfigured: false,
    ShopifyCustomerAccountFailure.notSignedIn: false,
    ShopifyCustomerAccountFailure.apiError: false,
  };

  test('every failure is classified', () {
    expect(expected.length, ShopifyCustomerAccountFailure.values.length,
        reason: 'add the new failure to the expected map');
    expect(expected.keys, containsAll(ShopifyCustomerAccountFailure.values));
  });

  test('isCancelled is true only for a dismissal or a timeout', () {
    for (final entry in expected.entries) {
      expect(
        ShopifyCustomerAccountException(entry.key, 'x').isCancelled,
        entry.value,
        reason: entry.key.name,
      );
    }
  });

  test('browserUnavailable is a host failure, not a shopper cancellation', () {
    const e = ShopifyCustomerAccountException(
        ShopifyCustomerAccountFailure.browserUnavailable, 'popup blocked');
    expect(e.isCancelled, isFalse);
    expect(e.toString(),
        'ShopifyCustomerAccountException(browserUnavailable): popup blocked');
  });
}
