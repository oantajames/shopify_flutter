import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shopify_flutter/mixins/src/shopify_error.dart';
import 'package:shopify_flutter/models/models.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_api.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_auth.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_browser.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_config.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_endpoints.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_exception.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_token_store.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_tokens.dart';

class _NoBrowser implements ShopifyCustomerAccountBrowser {
  @override
  Future<Uri> authorize(Uri url, Uri redirectUri,
          {Duration timeout = const Duration(minutes: 5)}) =>
      throw UnimplementedError();

  @override
  Future<void> logout(Uri url, Uri redirectUri,
      {Duration timeout = const Duration(seconds: 10)}) async {}

  @override
  Future<void> cancelPending() async {}
}

void main() {
  const config = ShopifyCustomerAccountConfig(
      shopDomain: 'demo.myshopify.com', shopId: '12345', clientId: 'cid');
  final endpoints = ShopifyCustomerAccountEndpoints.defaults(config);

  late InMemoryCustomerAccountTokenStore store;
  late List<http.Request> requests;

  ShopifyCustomerAccountApi build(
      Map<String, dynamic> Function(String op) reply) {
    final client = MockClient((request) async {
      requests.add(request);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final op = RegExp(r'(query|mutation)\s+(\w+)')
          .firstMatch(body['query'] as String)!
          .group(2)!;
      return http.Response(jsonEncode({'data': reply(op)}), 200);
    });
    final auth = ShopifyCustomerAccountAuth(
      config: config,
      endpoints: endpoints,
      browser: _NoBrowser(),
      tokenStore: store,
      client: client,
    );
    return ShopifyCustomerAccountApi(
        auth: auth, endpoints: endpoints, client: client);
  }

  setUp(() async {
    store = InMemoryCustomerAccountTokenStore();
    requests = [];
    await store.write(
      config.storageKey,
      ShopifyCustomerAccountTokens(
          accessToken: 'tok',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1))),
    );
  });

  test('getCustomer sends the token in Authorization and maps the customer',
      () async {
    final api = build((_) => {
          'customer': {
            'id': 'gid://shopify/Customer/1',
            'firstName': 'Ana',
            'emailAddress': {'emailAddress': 'ana@example.com'},
          }
        });
    final user = await api.getCustomer();
    expect(user.email, 'ana@example.com');
    expect(requests.single.url, endpoints.graphql);
    expect(requests.single.headers['Authorization'], 'tok');
  });

  test('getCustomer throws notConfigured-free apiError when signed out',
      () async {
    await store.clear(config.storageKey);
    final api = build((_) => {});
    expect(
      () => api.getCustomer(),
      throwsA(isA<ShopifyCustomerAccountException>().having(
          (e) => e.reason, 'reason', ShopifyCustomerAccountFailure.apiError)),
    );
  });

  test('userErrors become ShopifyException', () async {
    final api = build((op) => {
          'customerAddressCreate': {
            'customerAddress': null,
            'userErrors': [
              {
                'field': ['address', 'zip'],
                'message': 'Zip is invalid'
              }
            ]
          }
        });
    expect(
      () => api.createAddress(Address(zip: 'x')),
      throwsA(isA<ShopifyException>()),
    );
  });

  test('createAddress maps input and result', () async {
    final api = build((op) => {
          'customerAddressCreate': {
            'customerAddress': {
              'id': 'gid://shopify/CustomerAddress/9',
              'address1': 'A1',
              'territoryCode': 'RO',
            },
            'userErrors': []
          }
        });
    final created = await api.createAddress(
        Address(address1: 'A1', countryCode: 'RO'),
        isDefault: true);
    expect(created.id, 'gid://shopify/CustomerAddress/9');
    final vars = (jsonDecode(requests.single.body) as Map)['variables'] as Map;
    expect(vars['address'], {'address1': 'A1', 'territoryCode': 'RO'});
    expect(vars['defaultAddress'], true);
  });

  test('getOrders pages until hasNextPage is false', () async {
    var call = 0;
    final api = build((op) {
      call++;
      return {
        'customer': {
          'orders': {
            'pageInfo': {'hasNextPage': call == 1, 'endCursor': 'c$call'},
            'edges': [
              {
                'cursor': 'c$call',
                'node': {
                  'id': 'gid://shopify/Order/$call',
                  'name': '#$call',
                  'number': call,
                  'currencyCode': 'RON',
                  'processedAt': '2026-01-01T00:00:00Z',
                  'financialStatus': 'PAID',
                  'fulfillmentStatus': 'FULFILLED',
                  'statusPageUrl': 'https://s/$call',
                  'totalPrice': {'amount': '1.0', 'currencyCode': 'RON'},
                  'subtotal': {'amount': '1.0', 'currencyCode': 'RON'},
                  'totalShipping': {'amount': '0.0', 'currencyCode': 'RON'},
                  'totalTax': {'amount': '0.0', 'currencyCode': 'RON'},
                  'totalRefunded': {'amount': '0.0', 'currencyCode': 'RON'},
                  'lineItems': {'edges': []},
                  'fulfillments': {'edges': []},
                }
              }
            ]
          }
        }
      };
    });
    final orders = await api.getOrders();
    expect(orders.map((o) => o.orderNumber), [1, 2]);
    final secondVars =
        (jsonDecode(requests[1].body) as Map)['variables'] as Map;
    expect(secondVars['after'], 'c1');
  });
}
