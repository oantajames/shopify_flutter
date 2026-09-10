import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:shopify_flutter/shopify/src/customer_account/pkce.dart';

class _FakeBrowser implements ShopifyCustomerAccountBrowser {
  Uri? lastAuthorizeUrl;
  Uri? lastLogoutUrl;
  Uri Function(Uri url, Uri redirectUri)? onAuthorize;

  @override
  Future<Uri> authorize(Uri url, Uri redirectUri,
      {Duration timeout = const Duration(minutes: 5)}) async {
    lastAuthorizeUrl = url;
    lastAuthorizeRedirectUri = redirectUri;
    return onAuthorize!(url, redirectUri);
  }

  Uri? lastAuthorizeRedirectUri;
  Uri? lastLogoutRedirectUri;

  @override
  Future<void> logout(Uri url, Uri redirectUri,
      {Duration timeout = const Duration(seconds: 10)}) async {
    lastLogoutUrl = url;
    lastLogoutRedirectUri = redirectUri;
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

  test('signIn and signOut carry custom https redirects end to end', () async {
    final redirect = Uri.parse('https://shop.example.com/auth/callback');
    final logout = Uri.parse('https://shop.example.com/auth/logged-out');
    final webConfig = ShopifyCustomerAccountConfig(
      shopDomain: 'demo.myshopify.com',
      shopId: '12345',
      clientId: 'cid',
      customRedirectUri: redirect,
      customLogoutRedirectUri: logout,
    );
    final auth = ShopifyCustomerAccountAuth(
      config: webConfig,
      endpoints: ShopifyCustomerAccountEndpoints.defaults(webConfig),
      browser: browser,
      tokenStore: store,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
            jsonEncode({
              'access_token': 'at1',
              'refresh_token': 'rt1',
              'id_token': 'idt1',
              'expires_in': 7200,
            }),
            200);
      }),
    );
    browser.onAuthorize = (url, redirectUri) => redirect.replace(
            queryParameters: {
              'code': 'the-code',
              'state': url.queryParameters['state']!
            });

    await auth.signIn();
    expect(browser.lastAuthorizeUrl!.queryParameters['redirect_uri'],
        redirect.toString());
    expect(browser.lastAuthorizeRedirectUri, same(redirect));
    expect(Uri.splitQueryString(requests.single.body)['redirect_uri'],
        redirect.toString());
    expect(await store.read(webConfig.storageKey), isNotNull);

    await auth.signOut();
    expect(browser.lastLogoutUrl!.queryParameters['post_logout_redirect_uri'],
        logout.toString());
    expect(browser.lastLogoutRedirectUri, same(logout));
    expect(await store.read(webConfig.storageKey), isNull);
  });

  test('signIn rethrows browserUnavailable unchanged and stays usable',
      () async {
    var tokenCalls = 0;
    final auth = build((_) async {
      tokenCalls++;
      return http.Response(
          jsonEncode({'access_token': 'at1', 'expires_in': 7200}), 200);
    });
    const unavailable = ShopifyCustomerAccountException(
        ShopifyCustomerAccountFailure.browserUnavailable, 'popup blocked');
    browser.onAuthorize = (_, __) => throw unavailable;

    await expectLater(auth.signIn(), throwsA(same(unavailable)));
    expect(tokenCalls, 0);
    expect(await store.read(config.storageKey), isNull);
    expect(await auth.isSignedIn, isFalse);

    // The failed attempt released the sign-in guard.
    browser.onAuthorize = (url, _) => Uri.parse(
        'shop.12345.app://callback?code=c&state=${url.queryParameters['state']}');
    final tokens = await auth.signIn();
    expect(tokens.accessToken, 'at1');
    expect(tokenCalls, 1);
  });

  test('signIn sends the verifier that matches the authorize challenge',
      () async {
    late String verifier;
    final auth = build((request) async {
      verifier = Uri.splitQueryString(request.body)['code_verifier']!;
      return http.Response(
          jsonEncode({'access_token': 'at1', 'expires_in': 7200}), 200);
    });
    browser.onAuthorize = (url, _) => Uri.parse(
        'shop.12345.app://callback?code=the-code&state=${url.queryParameters['state']}');

    await auth.signIn();

    expect(Pkce.challengeFor(verifier),
        browser.lastAuthorizeUrl!.queryParameters['code_challenge']);
  });

  test('a second signIn while one is pending is rejected', () async {
    final gate = Completer<void>();
    final auth = build((_) async {
      await gate.future;
      return http.Response(
          jsonEncode({'access_token': 'at1', 'expires_in': 7200}), 200);
    });
    browser.onAuthorize = (url, _) => Uri.parse(
        'shop.12345.app://callback?code=the-code&state=${url.queryParameters['state']}');

    final first = auth.signIn();
    await expectLater(
      auth.signIn(),
      throwsA(isA<ShopifyCustomerAccountException>().having(
          (e) => e.message, 'message', contains('already in progress'))),
    );
    gate.complete();

    expect((await first).accessToken, 'at1');
    expect(requests, hasLength(1));
  });

  test(
      'signIn reports a state mismatch even when the callback carries an error',
      () async {
    final auth = build((_) async => fail('token endpoint must not be called'));
    browser.onAuthorize = (_, __) =>
        Uri.parse('shop.12345.app://callback?error=access_denied&state=wrong');
    await expectLater(
      auth.signIn(),
      throwsA(isA<ShopifyCustomerAccountException>().having((e) => e.reason,
          'reason', ShopifyCustomerAccountFailure.stateMismatch)),
    );
  });

  test('concurrent accessToken reads share a single refresh', () async {
    await store.write(
        config.storageKey,
        _tokens('old',
            refreshToken: 'rt1', expiresIn: const Duration(seconds: 30)));
    final auth = build((_) async => http.Response(
        jsonEncode({'access_token': 'new', 'expires_in': 7200}), 200));

    final results = await Future.wait(
        [auth.accessToken, auth.accessToken, auth.accessToken]);

    expect(results, ['new', 'new', 'new']);
    expect(requests, hasLength(1));
  });

  test('signOut during an in-flight refresh keeps the session cleared',
      () async {
    await store.write(
        config.storageKey,
        _tokens('old',
            refreshToken: 'rt1', expiresIn: const Duration(seconds: 30)));
    final started = Completer<void>();
    final gate = Completer<void>();
    final auth = build((_) async {
      started.complete();
      await gate.future;
      return http.Response(
          jsonEncode({'access_token': 'new', 'expires_in': 7200}), 200);
    });

    final pending = auth.accessToken;
    await started.future;
    await auth.signOut();
    gate.complete();

    expect(await pending, isNull);
    expect(await store.read(config.storageKey), isNull);
  });

  test('signOut requested before a refresh starts still wins', () async {
    await store.write(
        config.storageKey,
        _tokens('old',
            refreshToken: 'rt1', expiresIn: const Duration(seconds: 30)));
    final gate = Completer<void>();
    final auth = build((_) async {
      await gate.future;
      return http.Response(
          jsonEncode({'access_token': 'new', 'expires_in': 7200}), 200);
    });

    final pending = auth.accessToken;
    await auth.signOut();
    gate.complete();

    expect(await pending, isNull);
    expect(await store.read(config.storageKey), isNull);
  });

  test('a refresh that outlives a sign out never overwrites the next session',
      () async {
    await store.write(
        config.storageKey,
        _tokens('old',
            refreshToken: 'rt1', expiresIn: const Duration(seconds: 30)));
    final refreshStarted = Completer<void>();
    final gate = Completer<void>();
    final auth = build((request) async {
      if (Uri.splitQueryString(request.body)['grant_type'] == 'refresh_token') {
        refreshStarted.complete();
        await gate.future;
        return http.Response(
            jsonEncode({'access_token': 'stale', 'expires_in': 7200}), 200);
      }
      return http.Response(
          jsonEncode({'access_token': 'fresh', 'expires_in': 7200}), 200);
    });
    browser.onAuthorize = (url, _) => Uri.parse(
        'shop.12345.app://callback?code=the-code&state=${url.queryParameters['state']}');

    final pending = auth.accessToken;
    await refreshStarted.future;
    await auth.signOut();
    await auth.signIn();
    gate.complete();

    expect(await pending, isNull);
    expect((await store.read(config.storageKey))!.accessToken, 'fresh');
  });

  test('a stale refresh completing does not drop the next session\'s refresh',
      () async {
    await store.write(
        config.storageKey,
        _tokens('old',
            refreshToken: 'rt1', expiresIn: const Duration(seconds: 30)));
    final staleStarted = Completer<void>();
    final staleGate = Completer<void>();
    final freshStarted = Completer<void>();
    final freshGate = Completer<void>();
    var refreshCalls = 0;
    final auth = build((request) async {
      final body = Uri.splitQueryString(request.body);
      if (body['grant_type'] != 'refresh_token') {
        return http.Response(
            jsonEncode({
              'access_token': 'fresh',
              'refresh_token': 'rt2',
              'expires_in': 30,
            }),
            200);
      }
      refreshCalls++;
      if (refreshCalls == 1) {
        staleStarted.complete();
        await staleGate.future;
        return http.Response(
            jsonEncode({'access_token': 'stale', 'expires_in': 7200}), 200);
      }
      if (!freshStarted.isCompleted) freshStarted.complete();
      await freshGate.future;
      return http.Response(
          jsonEncode({'access_token': 'refreshed', 'expires_in': 7200}), 200);
    });
    browser.onAuthorize = (url, _) => Uri.parse(
        'shop.12345.app://callback?code=the-code&state=${url.queryParameters['state']}');

    final stale = auth.accessToken;
    await staleStarted.future;
    await auth.signOut();
    await auth.signIn();

    // The new session's refresh is in flight when the stale one completes.
    final first = auth.accessToken;
    await freshStarted.future;
    staleGate.complete();
    expect(await stale, isNull);

    final second = auth.accessToken;
    freshGate.complete();

    expect(await first, 'refreshed');
    expect(await second, 'refreshed');
    expect(refreshCalls, 2);
  });

  test('a 200 that is not json on refresh keeps the session', () async {
    final stored = _tokens('old',
        refreshToken: 'rt1', expiresIn: const Duration(seconds: 30));
    await store.write(config.storageKey, stored);
    final auth = build((_) async => http.Response('<html>', 200));

    expect(await auth.accessToken, 'old');
    expect(await store.read(config.storageKey), stored);
  });

  test('a transport failure keeps a still-valid session', () async {
    final stored = _tokens('old',
        refreshToken: 'rt1', expiresIn: const Duration(seconds: 30));
    await store.write(config.storageKey, stored);
    final auth = build((_) async => throw const SocketException('offline'));

    expect(await auth.accessToken, 'old');
    expect(await store.read(config.storageKey), stored);
  });

  test('a transport failure on an expired session keeps the tokens for a retry',
      () async {
    final stored = _tokens('old',
        refreshToken: 'rt1', expiresIn: const Duration(minutes: -1));
    await store.write(config.storageKey, stored);
    final auth = build((_) async => throw const SocketException('offline'));

    expect(await auth.accessToken, isNull);
    expect(await store.read(config.storageKey), stored);
  });

  test('a 5xx from the token endpoint keeps the session', () async {
    final stored = _tokens('old',
        refreshToken: 'rt1', expiresIn: const Duration(seconds: 30));
    await store.write(config.storageKey, stored);
    final auth = build((_) async => http.Response('upstream boom', 503));

    expect(await auth.accessToken, 'old');
    expect(await store.read(config.storageKey), stored);
  });
}

ShopifyCustomerAccountTokens _tokens(
  String accessToken, {
  required Duration expiresIn,
  String? refreshToken,
  String? idToken,
}) =>
    ShopifyCustomerAccountTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken,
      expiresAt: DateTime.now().toUtc().add(expiresIn),
    );
