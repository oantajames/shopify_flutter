import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_auth.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_browser.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_config.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_endpoints.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_exception.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_token_store.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_tokens.dart';

class _FakeBrowser implements ShopifyCustomerAccountBrowser {
  Uri? lastAuthorizeUrl;
  Uri? lastLogoutUrl;
  Uri Function(Uri url, Uri redirectUri)? onAuthorize;

  @override
  Future<Uri> authorize(Uri url, Uri redirectUri,
      {Duration timeout = const Duration(minutes: 5)}) async {
    lastAuthorizeUrl = url;
    return onAuthorize!(url, redirectUri);
  }

  @override
  Future<void> logout(Uri url, Uri redirectUri,
      {Duration timeout = const Duration(seconds: 10)}) async {
    lastLogoutUrl = url;
  }

  @override
  Future<void> cancelPending() async {}
}

void main() {
  const config = ShopifyCustomerAccountConfig(
      shopDomain: 'demo.myshopify.com', shopId: '12345', clientId: 'cid');
  final endpoints = ShopifyCustomerAccountEndpoints.defaults(config);

  late _FakeBrowser browser;
  late InMemoryCustomerAccountTokenStore store;
  late List<http.Request> requests;

  ShopifyCustomerAccountAuth build(
      Future<http.Response> Function(http.Request) handler) {
    return ShopifyCustomerAccountAuth(
      config: config,
      endpoints: endpoints,
      browser: browser,
      tokenStore: store,
      client: MockClient((request) {
        requests.add(request);
        return handler(request);
      }),
    );
  }

  setUp(() {
    browser = _FakeBrowser();
    store = InMemoryCustomerAccountTokenStore();
    requests = [];
  });

  test(
      'signIn builds authorize url with pkce, state and login hint, then exchanges',
      () async {
    final auth = build((request) async {
      expect(request.url, endpoints.token);
      final body = Uri.splitQueryString(request.body);
      expect(body['grant_type'], 'authorization_code');
      expect(body['client_id'], 'cid');
      expect(body['redirect_uri'], 'shop.12345.app://callback');
      expect(body['code'], 'the-code');
      expect(body['code_verifier'], isNotEmpty);
      return http.Response(
          jsonEncode({
            'access_token': 'at1',
            'refresh_token': 'rt1',
            'id_token': 'idt1',
            'expires_in': 7200,
          }),
          200);
    });
    browser.onAuthorize = (url, redirectUri) {
      expect(url.queryParameters['client_id'], 'cid');
      expect(url.queryParameters['response_type'], 'code');
      expect(url.queryParameters['scope'],
          'openid email customer-account-api:full');
      expect(url.queryParameters['redirect_uri'], 'shop.12345.app://callback');
      expect(url.queryParameters['code_challenge_method'], 'S256');
      expect(url.queryParameters['code_challenge'], isNotEmpty);
      expect(url.queryParameters['nonce'], isNotEmpty);
      expect(url.queryParameters['login_hint'], 'me@example.com');
      final state = url.queryParameters['state']!;
      return Uri.parse('shop.12345.app://callback?code=the-code&state=$state');
    };

    final tokens = await auth.signIn(loginHint: 'me@example.com');
    expect(tokens.accessToken, 'at1');
    expect(await store.read(config.storageKey), tokens);
    expect(await auth.isSignedIn, isTrue);
  });

  test('signIn rejects a state mismatch without calling the token endpoint',
      () async {
    final auth = build((_) async => fail('token endpoint must not be called'));
    browser.onAuthorize =
        (_, __) => Uri.parse('shop.12345.app://callback?code=x&state=wrong');
    expect(
      () => auth.signIn(),
      throwsA(isA<ShopifyCustomerAccountException>().having((e) => e.reason,
          'reason', ShopifyCustomerAccountFailure.stateMismatch)),
    );
  });

  test('signIn surfaces an error query param as exchangeFailed', () async {
    final auth = build((_) async => fail('token endpoint must not be called'));
    browser.onAuthorize = (url, _) => Uri.parse(
        'shop.12345.app://callback?error=access_denied&state=${url.queryParameters['state']}');
    expect(
      () => auth.signIn(),
      throwsA(isA<ShopifyCustomerAccountException>().having((e) => e.reason,
          'reason', ShopifyCustomerAccountFailure.exchangeFailed)),
    );
  });

  test('accessToken refreshes when expiring soon and keeps the refresh token',
      () async {
    await store.write(
      config.storageKey,
      ShopifyCustomerAccountTokens(
        accessToken: 'old',
        refreshToken: 'rt1',
        expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 30)),
      ),
    );
    final auth = build((request) async {
      final body = Uri.splitQueryString(request.body);
      expect(body['grant_type'], 'refresh_token');
      expect(body['refresh_token'], 'rt1');
      expect(body['client_id'], 'cid');
      return http.Response(
          jsonEncode({'access_token': 'new', 'expires_in': 7200}), 200);
    });
    expect(await auth.accessToken, 'new');
    expect((await store.read(config.storageKey))!.refreshToken, 'rt1');
  });

  test('accessToken clears the session when refresh fails', () async {
    await store.write(
      config.storageKey,
      ShopifyCustomerAccountTokens(
        accessToken: 'old',
        refreshToken: 'rt1',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      ),
    );
    final auth =
        build((_) async => http.Response('{"error":"invalid_grant"}', 400));
    expect(await auth.accessToken, isNull);
    expect(await store.read(config.storageKey), isNull);
  });

  test('accessToken returns null without a refresh token once expired',
      () async {
    await store.write(
      config.storageKey,
      ShopifyCustomerAccountTokens(
        accessToken: 'old',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      ),
    );
    final auth = build((_) async => fail('no network call expected'));
    expect(await auth.accessToken, isNull);
  });

  test('signOut clears tokens and opens the logout url with id_token_hint',
      () async {
    await store.write(
      config.storageKey,
      ShopifyCustomerAccountTokens(
        accessToken: 'at',
        idToken: 'idt',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );
    final auth = build((_) async => fail('no network call expected'));
    await auth.signOut();
    expect(await store.read(config.storageKey), isNull);
    expect(browser.lastLogoutUrl!.queryParameters['id_token_hint'], 'idt');
    expect(browser.lastLogoutUrl!.queryParameters['post_logout_redirect_uri'],
        'shop.12345.app://logout');
  });
}
