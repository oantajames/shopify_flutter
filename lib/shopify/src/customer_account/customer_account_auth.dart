import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'customer_account_browser.dart';
import 'customer_account_config.dart';
import 'customer_account_endpoints.dart';
import 'customer_account_exception.dart';
import 'customer_account_token_store.dart';
import 'customer_account_tokens.dart';
import 'pkce.dart';

/// OAuth 2.0 authorization-code + PKCE client for Shopify's Customer Account
/// API. Holds no UI: the browser round trip is delegated to
/// [ShopifyCustomerAccountBrowser].
class ShopifyCustomerAccountAuth {
  /// Scope granting full Customer Account API access.
  static const String scope = 'openid email customer-account-api:full';

  /// Shop domain, shop id, client id and the derived redirect URIs.
  final ShopifyCustomerAccountConfig config;

  /// The authorize, token and logout endpoints to call.
  final ShopifyCustomerAccountEndpoints endpoints;

  /// Opens Shopify's hosted pages and reports the redirect back.
  final ShopifyCustomerAccountBrowser browser;

  /// Where the issued tokens are persisted.
  final ShopifyCustomerAccountTokenStore tokenStore;

  final http.Client _client;

  Future<ShopifyCustomerAccountTokens?>? _refreshing;

  /// Creates an auth client for one shop.
  ShopifyCustomerAccountAuth({
    required this.config,
    required this.endpoints,
    required this.browser,
    this.tokenStore = const SharedPreferencesCustomerAccountTokenStore(),
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Builds the authorize URL for one attempt.
  Uri buildAuthorizeUrl({
    required Pkce pkce,
    required String state,
    required String nonce,
    String? loginHint,
    String? locale,
  }) =>
      endpoints.authorize.replace(queryParameters: {
        'client_id': config.clientId,
        'response_type': 'code',
        'redirect_uri': config.redirectUri.toString(),
        'scope': scope,
        'state': state,
        'nonce': nonce,
        'code_challenge': pkce.challenge,
        'code_challenge_method': 'S256',
        if (loginHint != null && loginHint.isNotEmpty) 'login_hint': loginHint,
        if (locale != null && locale.isNotEmpty) 'locale': locale,
      });

  /// Runs the hosted login and stores the resulting tokens.
  Future<ShopifyCustomerAccountTokens> signIn({
    String? loginHint,
    String? locale,
  }) async {
    final pkce = Pkce.generate();
    final state = Pkce.randomToken();
    final nonce = Pkce.randomToken();
    final url = buildAuthorizeUrl(
      pkce: pkce,
      state: state,
      nonce: nonce,
      loginHint: loginHint,
      locale: locale,
    );

    final callback = await browser.authorize(url, config.redirectUri);
    final params = callback.queryParameters;
    if (params['error'] != null) {
      throw ShopifyCustomerAccountException(
        ShopifyCustomerAccountFailure.exchangeFailed,
        params['error_description'] ?? params['error']!,
      );
    }
    if (params['state'] != state) {
      throw const ShopifyCustomerAccountException(
        ShopifyCustomerAccountFailure.stateMismatch,
        'Authorization state did not match',
      );
    }
    final code = params['code'];
    if (code == null || code.isEmpty) {
      throw const ShopifyCustomerAccountException(
        ShopifyCustomerAccountFailure.exchangeFailed,
        'Authorization callback did not contain a code',
      );
    }

    final tokens = await _postToken({
      'grant_type': 'authorization_code',
      'client_id': config.clientId,
      'redirect_uri': config.redirectUri.toString(),
      'code': code,
      'code_verifier': pkce.verifier,
    }, failure: ShopifyCustomerAccountFailure.exchangeFailed);
    await tokenStore.write(config.storageKey, tokens);
    return tokens;
  }

  /// Current access token, refreshed when expiring. Null when signed out or
  /// when refresh is impossible (the stored session is cleared in that case).
  Future<String?> get accessToken async {
    final tokens = await tokenStore.read(config.storageKey);
    if (tokens == null) return null;
    if (!tokens.isExpiringSoon()) return tokens.accessToken;
    final refreshed = await _refreshOnce(tokens);
    return refreshed?.accessToken;
  }

  /// Stored tokens without refreshing (for id_token access etc).
  Future<ShopifyCustomerAccountTokens?> get storedTokens =>
      tokenStore.read(config.storageKey);

  /// Whether a usable (or refreshable) access token is available.
  Future<bool> get isSignedIn async => (await accessToken) != null;

  /// Forces a refresh; clears the session and returns null on failure.
  Future<ShopifyCustomerAccountTokens?> refresh() async {
    final tokens = await tokenStore.read(config.storageKey);
    if (tokens == null) return null;
    return _refreshOnce(tokens);
  }

  Future<ShopifyCustomerAccountTokens?> _refreshOnce(
      ShopifyCustomerAccountTokens tokens) {
    return _refreshing ??=
        _doRefresh(tokens).whenComplete(() => _refreshing = null);
  }

  Future<ShopifyCustomerAccountTokens?> _doRefresh(
      ShopifyCustomerAccountTokens tokens) async {
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      if (tokens.isExpired()) {
        await tokenStore.clear(config.storageKey);
        return null;
      }
      return tokens;
    }
    try {
      final refreshed = await _postToken({
        'grant_type': 'refresh_token',
        'client_id': config.clientId,
        'refresh_token': refreshToken,
      },
          failure: ShopifyCustomerAccountFailure.refreshFailed,
          previous: tokens);
      await tokenStore.write(config.storageKey, refreshed);
      return refreshed;
    } on ShopifyCustomerAccountException {
      await tokenStore.clear(config.storageKey);
      return null;
    }
  }

  /// Aborts an in-progress [signIn] (the shopper tapped Cancel in the app).
  Future<void> cancelSignIn() => browser.cancelPending();

  /// Logout URL with `id_token_hint` and the post-logout redirect.
  Uri buildLogoutUrl(String? idToken) =>
      endpoints.logout.replace(queryParameters: {
        if (idToken != null && idToken.isNotEmpty) 'id_token_hint': idToken,
        'post_logout_redirect_uri': config.logoutRedirectUri.toString(),
      });

  /// Clears stored tokens, then ends the Shopify browser session best-effort.
  Future<void> signOut({bool endShopifySession = true}) async {
    final tokens = await tokenStore.read(config.storageKey);
    await tokenStore.clear(config.storageKey);
    if (!endShopifySession) return;
    try {
      await browser.logout(
          buildLogoutUrl(tokens?.idToken), config.logoutRedirectUri);
    } catch (_) {
      // Best effort only.
    }
  }

  Future<ShopifyCustomerAccountTokens> _postToken(
    Map<String, String> body, {
    required ShopifyCustomerAccountFailure failure,
    ShopifyCustomerAccountTokens? previous,
  }) async {
    final http.Response response;
    try {
      response = await _client.post(
        endpoints.token,
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: body,
      );
    } catch (e) {
      throw ShopifyCustomerAccountException(
          failure, 'Token request failed: $e');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ShopifyCustomerAccountException(failure,
          'Token endpoint returned ${response.statusCode}: ${response.body}');
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ShopifyCustomerAccountException(
          failure, 'Token endpoint returned invalid JSON');
    }
    if (json['access_token'] is! String) {
      throw ShopifyCustomerAccountException(failure,
          'Token endpoint response missing access_token: ${response.body}');
    }
    try {
      return ShopifyCustomerAccountTokens.fromTokenResponse(json,
          previous: previous);
    } on ShopifyCustomerAccountException catch (e) {
      // The factory reports `exchangeFailed`; report the caller's failure so a
      // refresh never surfaces as an exchange error.
      throw ShopifyCustomerAccountException(failure, e.message);
    }
  }
}
