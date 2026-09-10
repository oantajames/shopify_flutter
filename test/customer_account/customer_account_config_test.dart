import 'package:flutter_test/flutter_test.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_config.dart';

void main() {
  const config = ShopifyCustomerAccountConfig(
    shopDomain: 'demo.myshopify.com',
    shopId: '12345',
    clientId: 'client-abc',
  );

  group('defaults', () {
    test('derive the mobile custom-scheme redirects from the shop id', () {
      expect(config.callbackScheme, 'shop.12345.app');
      expect(config.redirectUri, Uri.parse('shop.12345.app://callback'));
      expect(config.logoutRedirectUri, Uri.parse('shop.12345.app://logout'));
    });

    test('leave the custom redirects unset', () {
      expect(config.customRedirectUri, isNull);
      expect(config.customLogoutRedirectUri, isNull);
    });

    test('key storage by shop domain', () {
      expect(config.customStorageKey, isNull);
      expect(config.storageKey, 'shopify_customer_account_demo.myshopify.com');
    });
  });

  group('custom storage key', () {
    const custom = ShopifyCustomerAccountConfig(
      shopDomain: 'demo.myshopify.com',
      shopId: '12345',
      clientId: 'client-abc',
      customStorageKey: 'shopify_customer_account_app_42',
    );

    test('is returned verbatim', () {
      expect(custom.storageKey, 'shopify_customer_account_app_42');
    });

    test('namespaces two apps for the same shop', () {
      const other = ShopifyCustomerAccountConfig(
        shopDomain: 'demo.myshopify.com',
        shopId: '12345',
        clientId: 'client-xyz',
        customStorageKey: 'shopify_customer_account_app_43',
      );
      expect(custom.storageKey, isNot(other.storageKey));
      expect(custom.storageKey, isNot(config.storageKey));
    });

    test('leaves the redirects and scheme unchanged', () {
      expect(custom.callbackScheme, 'shop.12345.app');
      expect(custom.redirectUri, Uri.parse('shop.12345.app://callback'));
      expect(custom.logoutRedirectUri, Uri.parse('shop.12345.app://logout'));
    });
  });

  group('custom redirects', () {
    final redirect = Uri.parse('https://shop.example.com/auth/callback');
    final logout = Uri.parse('https://shop.example.com/auth/logged-out');
    final custom = ShopifyCustomerAccountConfig(
      shopDomain: 'demo.myshopify.com',
      shopId: '12345',
      clientId: 'client-abc',
      customRedirectUri: redirect,
      customLogoutRedirectUri: logout,
    );

    test('are returned verbatim', () {
      expect(custom.redirectUri, same(redirect));
      expect(custom.logoutRedirectUri, same(logout));
    });

    test('may override only the callback', () {
      final only = ShopifyCustomerAccountConfig(
        shopDomain: 'demo.myshopify.com',
        shopId: '12345',
        clientId: 'client-abc',
        customRedirectUri: redirect,
      );
      expect(only.redirectUri, same(redirect));
      expect(only.logoutRedirectUri, Uri.parse('shop.12345.app://logout'));
    });

    test('may override only the logout redirect', () {
      final only = ShopifyCustomerAccountConfig(
        shopDomain: 'demo.myshopify.com',
        shopId: '12345',
        clientId: 'client-abc',
        customLogoutRedirectUri: logout,
      );
      expect(only.redirectUri, Uri.parse('shop.12345.app://callback'));
      expect(only.logoutRedirectUri, same(logout));
    });

    test('leave the mobile scheme and storage key unchanged', () {
      expect(custom.callbackScheme, 'shop.12345.app');
      expect(custom.storageKey, config.storageKey);
    });
  });
}
