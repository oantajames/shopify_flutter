import 'customer_account_config.dart';

/// The four Customer Account API endpoints for one shop.
class ShopifyCustomerAccountEndpoints {
  /// The OAuth 2.0 authorization endpoint.
  final Uri authorize;

  /// The OAuth 2.0 token endpoint.
  final Uri token;

  /// The logout endpoint.
  final Uri logout;

  /// The Customer Account API GraphQL endpoint.
  final Uri graphql;

  /// Creates an explicit set of Customer Account API endpoints.
  const ShopifyCustomerAccountEndpoints({
    required this.authorize,
    required this.token,
    required this.logout,
    required this.graphql,
  });

  /// The `https://shopify.com/{shopId}` forms used by Shopify's own Hydrogen
  /// client. Valid for every shop; used when no discovered endpoints exist.
  factory ShopifyCustomerAccountEndpoints.defaults(
      ShopifyCustomerAccountConfig config) {
    final auth = 'https://shopify.com/authentication/${config.shopId}';
    return ShopifyCustomerAccountEndpoints(
      authorize: Uri.parse('$auth/oauth/authorize'),
      token: Uri.parse('$auth/oauth/token'),
      logout: Uri.parse('$auth/logout'),
      graphql: Uri.parse(
          'https://shopify.com/${config.shopId}/account/customer/api/${config.apiVersion}/graphql'),
    );
  }

  /// Endpoints stored by the CMS after discovery (`customerAccountEndpoints`).
  factory ShopifyCustomerAccountEndpoints.fromJson(Map<String, dynamic> json) =>
      ShopifyCustomerAccountEndpoints(
        authorize: Uri.parse(json['authorize'] as String),
        token: Uri.parse(json['token'] as String),
        logout: Uri.parse(json['logout'] as String),
        graphql: Uri.parse(json['graphql'] as String),
      );

  /// Serializes these endpoints for CMS storage.
  Map<String, String> toJson() => {
        'authorize': authorize.toString(),
        'token': token.toString(),
        'logout': logout.toString(),
        'graphql': graphql.toString(),
      };
}
