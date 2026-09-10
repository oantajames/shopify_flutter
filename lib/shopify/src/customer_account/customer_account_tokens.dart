import 'dart:convert';

/// Tokens issued by the Customer Account API token endpoint.
class ShopifyCustomerAccountTokens {
  /// Seconds before [expiresAt] at which the token counts as expiring.
  static const Duration expiryBuffer = Duration(seconds: 120);

  /// The token used to authenticate Customer Account API requests.
  final String accessToken;

  /// The token used to obtain new tokens once [accessToken] expires.
  final String? refreshToken;

  /// The OpenID Connect identity token, if one was issued.
  final String? idToken;

  /// When [accessToken] expires.
  final DateTime expiresAt;

  /// Creates a set of Customer Account tokens.
  const ShopifyCustomerAccountTokens({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
    this.idToken,
  });

  /// Builds tokens from the token endpoint JSON body.
  factory ShopifyCustomerAccountTokens.fromTokenResponse(
    Map<String, dynamic> body, {
    DateTime? now,
    ShopifyCustomerAccountTokens? previous,
  }) {
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 0;
    return ShopifyCustomerAccountTokens(
      accessToken: body['access_token'] as String,
      refreshToken:
          (body['refresh_token'] as String?) ?? previous?.refreshToken,
      idToken: (body['id_token'] as String?) ?? previous?.idToken,
      expiresAt: (now ?? DateTime.now().toUtc())
          .add(Duration(seconds: expiresIn)),
    );
  }

  /// Whether [expiresAt] is in the past, relative to [now].
  bool isExpired({DateTime? now}) =>
      (now ?? DateTime.now().toUtc()).isAfter(expiresAt);

  /// Whether [expiresAt] is within [expiryBuffer] of [now].
  bool isExpiringSoon({DateTime? now}) =>
      (now ?? DateTime.now().toUtc()).add(expiryBuffer).isAfter(expiresAt);

  /// Converts these tokens to a JSON-compatible map.
  Map<String, dynamic> toMap() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'idToken': idToken,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
      };

  /// Builds tokens from a map previously produced by [toMap].
  factory ShopifyCustomerAccountTokens.fromMap(Map<String, dynamic> map) =>
      ShopifyCustomerAccountTokens(
        accessToken: map['accessToken'] as String,
        refreshToken: map['refreshToken'] as String?,
        idToken: map['idToken'] as String?,
        expiresAt: DateTime.parse(map['expiresAt'] as String).toUtc(),
      );

  /// Encodes these tokens as a JSON string.
  String toJson() => json.encode(toMap());

  /// Decodes tokens previously produced by [toJson].
  factory ShopifyCustomerAccountTokens.fromJson(String source) =>
      ShopifyCustomerAccountTokens.fromMap(
          json.decode(source) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      other is ShopifyCustomerAccountTokens &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.idToken == idToken &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(accessToken, refreshToken, idToken, expiresAt);
}
