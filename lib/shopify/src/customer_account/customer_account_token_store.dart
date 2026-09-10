import 'package:shared_preferences/shared_preferences.dart';

import 'customer_account_tokens.dart';

/// Persists Customer Account tokens.
abstract class ShopifyCustomerAccountTokenStore {
  /// Reads the tokens stored under [key], or `null` if none exist.
  Future<ShopifyCustomerAccountTokens?> read(String key);

  /// Persists [tokens] under [key].
  Future<void> write(String key, ShopifyCustomerAccountTokens tokens);

  /// Removes any tokens stored under [key].
  Future<void> clear(String key);
}

/// Default store, mirrors how [ShopifyAuth] persists the Storefront token.
class SharedPreferencesCustomerAccountTokenStore
    implements ShopifyCustomerAccountTokenStore {
  /// Creates a store backed by [SharedPreferences].
  const SharedPreferencesCustomerAccountTokenStore();

  @override
  Future<ShopifyCustomerAccountTokens?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return ShopifyCustomerAccountTokens.fromJson(raw);
    } catch (_) {
      await prefs.remove(key);
      return null;
    }
  }

  @override
  Future<void> write(String key, ShopifyCustomerAccountTokens tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, tokens.toJson());
  }

  @override
  Future<void> clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

/// Test double.
class InMemoryCustomerAccountTokenStore
    implements ShopifyCustomerAccountTokenStore {
  final Map<String, ShopifyCustomerAccountTokens> _data = {};

  @override
  Future<ShopifyCustomerAccountTokens?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, ShopifyCustomerAccountTokens tokens) async =>
      _data[key] = tokens;

  @override
  Future<void> clear(String key) async => _data.remove(key);
}
