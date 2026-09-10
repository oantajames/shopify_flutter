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

  /// Creates a Customer Account API configuration.
  const ShopifyCustomerAccountConfig({
    required this.shopDomain,
    required this.shopId,
    required this.clientId,
    this.apiVersion = defaultApiVersion,
  });

  /// Custom scheme required by Shopify for mobile callbacks: `shop.{shopId}.*`.
  String get callbackScheme => 'shop.$shopId.app';

  /// Redirect URI registered as a callback in Shopify.
  Uri get redirectUri => Uri.parse('$callbackScheme://callback');

  /// Redirect URI registered as the logout URI in Shopify.
  Uri get logoutRedirectUri => Uri.parse('$callbackScheme://logout');

  /// Storage key for persisted tokens.
  String get storageKey => 'shopify_customer_account_$shopDomain';
}
