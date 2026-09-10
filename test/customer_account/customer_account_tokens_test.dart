import 'package:flutter_test/flutter_test.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_config.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_endpoints.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_token_store.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_tokens.dart';

void main() {
  const config = ShopifyCustomerAccountConfig(
    shopDomain: 'demo.myshopify.com',
    shopId: '12345',
    clientId: 'client-abc',
  );

  test('config derives callback uris from shop id', () {
    expect(config.redirectUri.toString(), 'shop.12345.app://callback');
    expect(config.logoutRedirectUri.toString(), 'shop.12345.app://logout');
    expect(config.callbackScheme, 'shop.12345.app');
  });

  test('default endpoints use the shopify.com shop-id forms', () {
    final e = ShopifyCustomerAccountEndpoints.defaults(config);
    expect(e.authorize.toString(),
        'https://shopify.com/authentication/12345/oauth/authorize');
    expect(e.token.toString(),
        'https://shopify.com/authentication/12345/oauth/token');
    expect(e.logout.toString(),
        'https://shopify.com/authentication/12345/logout');
    expect(e.graphql.toString(),
        'https://shopify.com/12345/account/customer/api/2026-04/graphql');
  });

  test('endpoints from config override defaults', () {
    final e = ShopifyCustomerAccountEndpoints.fromJson({
      'authorize': 'https://demo.example/authentication/oauth/authorize',
      'token': 'https://demo.example/authentication/oauth/token',
      'logout': 'https://demo.example/authentication/logout',
      'graphql': 'https://demo.example/customer/api/2026-04/graphql',
    });
    expect(e.authorize.host, 'demo.example');
    expect(e.toJson()['graphql'],
        'https://demo.example/customer/api/2026-04/graphql');
  });

  test('tokens round-trip json and know when they expire', () {
    final now = DateTime.utc(2026, 9, 10, 12);
    final tokens = ShopifyCustomerAccountTokens.fromTokenResponse(
      {
        'access_token': 'at',
        'refresh_token': 'rt',
        'id_token': 'idt',
        'expires_in': 7200,
      },
      now: now,
    );
    expect(tokens.expiresAt, now.add(const Duration(seconds: 7200)));
    final restored =
        ShopifyCustomerAccountTokens.fromJson(tokens.toJson());
    expect(restored, tokens);
    expect(tokens.isExpiringSoon(now: now), isFalse);
    expect(
        tokens.isExpiringSoon(
            now: now.add(const Duration(seconds: 7200 - 119))),
        isTrue);
    expect(tokens.isExpired(now: now.add(const Duration(seconds: 7201))),
        isTrue);
  });

  test('in-memory store reads back what it wrote', () async {
    final store = InMemoryCustomerAccountTokenStore();
    expect(await store.read('demo'), isNull);
    final t = ShopifyCustomerAccountTokens(
        accessToken: 'a', expiresAt: DateTime.utc(2030));
    await store.write('demo', t);
    expect(await store.read('demo'), t);
    await store.clear('demo');
    expect(await store.read('demo'), isNull);
  });
}
