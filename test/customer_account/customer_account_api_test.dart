import 'dart:convert';
import 'dart:io';

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

  /// An api whose http client (and whose auth's token client) is [handler].
  ShopifyCustomerAccountApi buildRaw(
      Future<http.Response> Function(http.Request request) handler) {
    final client = MockClient((request) async {
      requests.add(request);
      return handler(request);
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

  /// An api that answers every GraphQL operation with `{'data': reply(op)}`.
  ShopifyCustomerAccountApi build(
          Map<String, dynamic> Function(String op) reply) =>
      buildRaw((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final op = RegExp(r'(query|mutation)\s+(\w+)')
            .firstMatch(body['query'] as String)!
            .group(2)!;
        return http.Response(jsonEncode({'data': reply(op)}), 200);
      });

  Map<String, dynamic> variablesOf(http.Request request) =>
      (jsonDecode(request.body) as Map)['variables'] as Map<String, dynamic>;

  Matcher throwsFailure(ShopifyCustomerAccountFailure reason) =>
      throwsA(isA<ShopifyCustomerAccountException>()
          .having((e) => e.reason, 'reason', reason));

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

  test('getCustomer throws notSignedIn when signed out', () async {
    await store.clear(config.storageKey);
    final api = build((_) => {});
    expect(() => api.getCustomer(),
        throwsFailure(ShopifyCustomerAccountFailure.notSignedIn));
  });

  test('getCustomer throws apiError when the response has no customer',
      () async {
    final api = build((_) => {'customer': null});
    expect(() => api.getCustomer(),
        throwsFailure(ShopifyCustomerAccountFailure.apiError));
  });

  test('graphql errors become an apiError', () async {
    final api = buildRaw((_) async => http.Response(
        jsonEncode({
          'errors': [
            {'message': 'Field is not defined'}
          ]
        }),
        200));
    expect(() => api.getCustomer(),
        throwsFailure(ShopifyCustomerAccountFailure.apiError));
  });

  test('a 500 is a network failure', () async {
    final api = buildRaw((_) async => http.Response('upstream boom', 500));
    expect(() => api.getCustomer(),
        throwsFailure(ShopifyCustomerAccountFailure.network));
  });

  test('a transport failure is a network failure', () async {
    final api = buildRaw((_) async => throw const SocketException('offline'));
    expect(() => api.getCustomer(),
        throwsFailure(ShopifyCustomerAccountFailure.network));
  });

  test('a 200 that is not json is a network failure', () async {
    final api = buildRaw((_) async => http.Response('<html>', 200));
    expect(() => api.getCustomer(),
        throwsFailure(ShopifyCustomerAccountFailure.network));
  });

  test('a 401 refreshes the token once and retries the request', () async {
    await store.write(
      config.storageKey,
      ShopifyCustomerAccountTokens(
          accessToken: 'stale',
          refreshToken: 'rt1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1))),
    );
    var graphqlCalls = 0;
    final api = buildRaw((request) async {
      if (request.url == endpoints.token) {
        return http.Response(
            jsonEncode({'access_token': 'fresh', 'expires_in': 7200}), 200);
      }
      graphqlCalls++;
      if (request.headers['Authorization'] != 'fresh') {
        return http.Response('{"errors":[{"message":"unauthorized"}]}', 401);
      }
      return http.Response(
          jsonEncode({
            'data': {
              'customer': {
                'id': 'gid://shopify/Customer/1',
                'emailAddress': {'emailAddress': 'ana@example.com'},
              }
            }
          }),
          200);
    });

    final user = await api.getCustomer();

    expect(user.email, 'ana@example.com');
    expect(graphqlCalls, 2);
    expect(requests.where((r) => r.url == endpoints.token), hasLength(1));
  });

  test('a 401 that survives the refresh is an apiError', () async {
    await store.write(
      config.storageKey,
      ShopifyCustomerAccountTokens(
          accessToken: 'stale',
          refreshToken: 'rt1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1))),
    );
    final api = buildRaw((request) async {
      if (request.url == endpoints.token) {
        return http.Response(
            jsonEncode({'access_token': 'fresh', 'expires_in': 7200}), 200);
      }
      return http.Response('nope', 401);
    });
    await expectLater(
      api.getCustomer(),
      throwsA(isA<ShopifyCustomerAccountException>()
          .having(
              (e) => e.reason, 'reason', ShopifyCustomerAccountFailure.apiError)
          .having((e) => e.message, 'message', contains('rejected the token'))),
    );
    expect(requests.where((r) => r.url == endpoints.graphql), hasLength(2));
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
    final vars = variablesOf(requests.single);
    expect(vars['address'], {'address1': 'A1', 'territoryCode': 'RO'});
    expect(vars['defaultAddress'], true);
  });

  test('createAddress throws apiError when no address comes back', () async {
    final api = build((op) => {
          'customerAddressCreate': {
            'customerAddress': null,
            'userErrors': [],
          }
        });
    expect(() => api.createAddress(Address(address1: 'A1')),
        throwsFailure(ShopifyCustomerAccountFailure.apiError));
  });

  test('updateAddress sends the id, the input and the default flag', () async {
    final api = build((op) => {
          'customerAddressUpdate': {
            'customerAddress': {
              'id': 'gid://shopify/CustomerAddress/9',
              'address1': 'A2',
            },
            'userErrors': []
          }
        });
    final updated = await api.updateAddress(
        Address(id: 'gid://shopify/CustomerAddress/9', address1: 'A2'),
        isDefault: false);
    expect(updated.address1, 'A2');
    final vars = variablesOf(requests.single);
    expect(vars['addressId'], 'gid://shopify/CustomerAddress/9');
    expect(vars['address'], {'address1': 'A2'});
    expect(vars['defaultAddress'], false);
  });

  test('updateAddress rejects an address without an id', () async {
    final api = build((op) => fail('no request expected'));
    expect(() => api.updateAddress(Address(address1: 'A2')),
        throwsA(isA<ArgumentError>()));
    expect(requests, isEmpty);
  });

  test('setDefaultAddress sends only the id and the default flag', () async {
    final api = build((op) => {
          'customerAddressUpdate': {
            'customerAddress': null,
            'userErrors': [],
          }
        });
    await api.setDefaultAddress('gid://shopify/CustomerAddress/9');
    final vars = variablesOf(requests.single);
    expect(vars['addressId'], 'gid://shopify/CustomerAddress/9');
    expect(vars['defaultAddress'], true);
    expect(vars.containsKey('address'), isFalse);
  });

  test('deleteAddress sends the address id', () async {
    final api = build((op) => {
          'customerAddressDelete': {
            'deletedAddressId': 'gid://shopify/CustomerAddress/9',
            'userErrors': [],
          }
        });
    await api.deleteAddress('gid://shopify/CustomerAddress/9');
    expect(variablesOf(requests.single)['addressId'],
        'gid://shopify/CustomerAddress/9');
  });

  test('updateCustomer sends only the given fields and re-reads the customer',
      () async {
    final api = build((op) => op == 'AppsCustomerUpdate'
        ? {
            'customerUpdate': {
              'customer': {'id': 'gid://shopify/Customer/1'},
              'userErrors': [],
            }
          }
        : {
            'customer': {
              'id': 'gid://shopify/Customer/1',
              'firstName': 'Ana',
            }
          });
    final user = await api.updateCustomer(firstName: 'Ana');
    expect(user.firstName, 'Ana');
    expect(variablesOf(requests.first)['input'], {'firstName': 'Ana'});
    expect(requests, hasLength(2));
  });

  test('getOrdersPage returns the page cursor and hasNextPage', () async {
    final api = build((op) => {
          'customer': {
            'orders': {
              'pageInfo': {'hasNextPage': true, 'endCursor': 'c1'},
              'edges': [
                {
                  'cursor': 'c1',
                  'node': {'id': 'gid://shopify/Order/1'}
                }
              ]
            }
          }
        });
    final page = await api.getOrdersPage(first: 1);
    expect(page.orders.single.id, 'gid://shopify/Order/1');
    expect(page.endCursor, 'c1');
    expect(page.hasNextPage, isTrue);
    expect(variablesOf(requests.single)['first'], 1);
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
    expect(variablesOf(requests[1])['after'], 'c1');
  });
}
