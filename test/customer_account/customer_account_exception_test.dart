import 'package:flutter_test/flutter_test.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_exception.dart';

void main() {
  const cancelledReasons = {
    ShopifyCustomerAccountFailure.cancelled,
    ShopifyCustomerAccountFailure.timeout,
  };

  test('isCancelled is true only for a dismissal or a timeout', () {
    for (final reason in ShopifyCustomerAccountFailure.values) {
      expect(
        ShopifyCustomerAccountException(reason, 'x').isCancelled,
        cancelledReasons.contains(reason),
        reason: '${reason.name} must be classified explicitly',
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
