/// Why a Customer Account operation failed.
enum ShopifyCustomerAccountFailure {
  /// The user dismissed the browser before completing the flow.
  cancelled,

  /// The flow did not complete before its timeout elapsed.
  timeout,

  /// The `state` returned by Shopify didn't match the one that was sent.
  stateMismatch,

  /// The authorization code could not be exchanged for tokens.
  exchangeFailed,

  /// The refresh token could not be exchanged for new tokens.
  refreshFailed,

  /// The request never reached a verdict: a transport error or a 5xx response.
  /// The stored session is kept so the call can be retried later.
  network,

  /// The Customer Account API has not been configured for this shop.
  notConfigured,

  /// There is no stored session, so the call was never attempted: the shopper
  /// has to sign in first.
  notSignedIn,

  /// The Customer Account API returned an error response.
  apiError,
}

/// Exception thrown by the customer_account module.
class ShopifyCustomerAccountException implements Exception {
  /// Why the operation failed.
  final ShopifyCustomerAccountFailure reason;

  /// A human-readable description of the failure.
  final String message;

  /// Creates a Customer Account exception with [reason] and [message].
  const ShopifyCustomerAccountException(this.reason, this.message);

  /// Whether this exception represents a user cancellation or a timeout.
  bool get isCancelled =>
      reason == ShopifyCustomerAccountFailure.cancelled ||
      reason == ShopifyCustomerAccountFailure.timeout;

  @override
  String toString() =>
      'ShopifyCustomerAccountException(${reason.name}): $message';
}
