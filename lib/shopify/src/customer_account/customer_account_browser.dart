/// Opens Shopify's hosted pages and reports the redirect back.
///
/// Implemented by the app (apps_core) so this package stays free of
/// platform plugins.
abstract class ShopifyCustomerAccountBrowser {
  /// Opens [url]; completes with the callback URI matching [redirectUri].
  /// Throws [ShopifyCustomerAccountException] with `cancelled` or `timeout`.
  Future<Uri> authorize(
    Uri url,
    Uri redirectUri, {
    Duration timeout = const Duration(minutes: 5),
  });

  /// Opens [url]; completes when [redirectUri] arrives or [timeout] elapses.
  /// Never throws.
  Future<void> logout(
    Uri url,
    Uri redirectUri, {
    Duration timeout = const Duration(seconds: 10),
  });

  /// Aborts a pending [authorize] with a `cancelled` failure and closes the
  /// browser view if one is open. No-op when nothing is pending.
  Future<void> cancelPending();
}
