/// Configuration for Shopify's Customer Account API (new customer accounts).
class ShopifyCustomerAccountConfig {
  /// Default Customer Account API version.
  static const String defaultApiVersion = '2026-04';

  /// The shop's domain, e.g. `demo.myshopify.com`.
  final String shopDomain;

  /// Numeric shop id (the number in `gid://shopify/Shop/{id}`).
  final String shopId;

  /// Client ID from the Headless channel's Customer Account API settings.
  final String clientId;

  /// Customer Account API version used for GraphQL calls.
  final String apiVersion;

  /// Overrides the mobile custom-scheme redirect, e.g. an HTTPS callback page
  /// for a web host. Must be registered in the Headless channel exactly as
  /// given.
  final Uri? customRedirectUri;

  /// Overrides the mobile custom-scheme logout redirect, e.g. an HTTPS
  /// logged-out page for a web host. Must be registered in the Headless
  /// channel exactly as given.
  final Uri? customLogoutRedirectUri;

  /// Creates a Customer Account API configuration.
  const ShopifyCustomerAccountConfig({
    required this.shopDomain,
    required this.shopId,
    required this.clientId,
    this.apiVersion = defaultApiVersion,
    this.customRedirectUri,
    this.customLogoutRedirectUri,
  });

  /// Custom scheme required by Shopify for mobile callbacks: `shop.{shopId}.*`.
  String get callbackScheme => 'shop.$shopId.app';

  /// Redirect URI registered as a callback in Shopify: [customRedirectUri]
  /// when set, otherwise `{callbackScheme}://callback`.
  Uri get redirectUri =>
      customRedirectUri ?? Uri.parse('$callbackScheme://callback');

  /// Redirect URI registered as the logout URI in Shopify:
  /// [customLogoutRedirectUri] when set, otherwise `{callbackScheme}://logout`.
  Uri get logoutRedirectUri =>
      customLogoutRedirectUri ?? Uri.parse('$callbackScheme://logout');

  /// Storage key for persisted tokens.
  String get storageKey => 'shopify_customer_account_$shopDomain';
}
