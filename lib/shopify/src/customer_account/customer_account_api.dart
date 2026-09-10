import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shopify_flutter/mixins/src/shopify_error.dart';
import 'package:shopify_flutter/models/models.dart';

import 'customer_account_auth.dart';
import 'customer_account_endpoints.dart';
import 'customer_account_exception.dart';
import 'customer_account_mappers.dart';
import 'customer_account_queries.dart';

/// One page of orders plus the cursor needed to ask for the next one.
class CustomerAccountOrdersPage {
  /// The orders in this page, newest first.
  final List<Order> orders;

  /// Cursor of the last edge, to pass back as `after`. Null on an empty page.
  final String? endCursor;

  /// Whether Shopify reported another page after this one.
  final bool hasNextPage;

  /// Creates a page of orders.
  const CustomerAccountOrdersPage({
    required this.orders,
    this.endCursor,
    this.hasNextPage = false,
  });
}

/// Customer Account API GraphQL client (profile, addresses, orders).
class ShopifyCustomerAccountApi {
  /// Supplies the access token every request is signed with.
  final ShopifyCustomerAccountAuth auth;

  /// The GraphQL endpoint to post to.
  final ShopifyCustomerAccountEndpoints endpoints;

  final http.Client _client;

  /// Creates an API client for one shop.
  ShopifyCustomerAccountApi({
    required this.auth,
    required this.endpoints,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// The signed-in customer's profile, default address and address book.
  Future<ShopifyUser> getCustomer() async {
    final data = await _run(CustomerAccountQueries.customer);
    final customer = data['customer'];
    if (customer is! Map<String, dynamic>) {
      throw const ShopifyCustomerAccountException(
          ShopifyCustomerAccountFailure.apiError, 'No customer in response');
    }
    return CustomerAccountMappers.customer(customer);
  }

  /// Updates the customer's name and returns the refreshed profile.
  Future<ShopifyUser> updateCustomer(
      {String? firstName, String? lastName}) async {
    final data = await _run(CustomerAccountQueries.customerUpdate, variables: {
      'input': {
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
      },
    });
    _throwUserErrors(data, 'customerUpdate');
    return getCustomer();
  }

  /// Adds [address] to the address book, optionally as the default one.
  Future<Address> createAddress(Address address,
      {bool isDefault = false}) async {
    final data = await _run(CustomerAccountQueries.addressCreate, variables: {
      'address': CustomerAccountMappers.addressInput(address),
      'defaultAddress': isDefault,
    });
    _throwUserErrors(data, 'customerAddressCreate');
    return _addressFrom(data, 'customerAddressCreate');
  }

  /// Edits the address identified by `address.id`, which must not be null.
  Future<Address> updateAddress(Address address, {bool? isDefault}) async {
    final addressId = address.id;
    if (addressId == null) throw ArgumentError.notNull('address.id');
    final data = await _run(CustomerAccountQueries.addressUpdate, variables: {
      'addressId': addressId,
      'address': CustomerAccountMappers.addressInput(address),
      if (isDefault != null) 'defaultAddress': isDefault,
    });
    _throwUserErrors(data, 'customerAddressUpdate');
    return _addressFrom(data, 'customerAddressUpdate');
  }

  /// Removes the address with [addressId] from the address book.
  Future<void> deleteAddress(String addressId) async {
    final data = await _run(CustomerAccountQueries.addressDelete,
        variables: {'addressId': addressId});
    _throwUserErrors(data, 'customerAddressDelete');
  }

  /// Makes the address with [addressId] the customer's default address.
  Future<void> setDefaultAddress(String addressId) async {
    final data = await _run(CustomerAccountQueries.addressUpdate, variables: {
      'addressId': addressId,
      'defaultAddress': true,
    });
    _throwUserErrors(data, 'customerAddressUpdate');
  }

  /// One page of orders, newest first. Pass the previous page's
  /// [CustomerAccountOrdersPage.endCursor] as [after] to continue.
  Future<CustomerAccountOrdersPage> getOrdersPage({
    int first = 25,
    String? after,
  }) async {
    final data = await _run(CustomerAccountQueries.orders,
        variables: {'first': first, 'after': after});
    final connection = data['customer']?['orders'] as Map<String, dynamic>?;
    if (connection == null) {
      return const CustomerAccountOrdersPage(orders: []);
    }
    final orders = [
      for (final edge in (connection['edges'] as List? ?? []))
        CustomerAccountMappers.order(edge as Map<String, dynamic>),
    ];
    final pageInfo = connection['pageInfo'] as Map<String, dynamic>?;
    return CustomerAccountOrdersPage(
      orders: orders,
      endCursor: pageInfo?['endCursor'] as String?,
      hasNextPage: pageInfo?['hasNextPage'] == true,
    );
  }

  /// Orders, newest first, following pagination for at most [maxPages] pages.
  Future<List<Order>> getOrders({int pageSize = 25, int maxPages = 10}) async {
    final orders = <Order>[];
    String? after;
    for (var page = 0; page < maxPages; page++) {
      final result = await getOrdersPage(first: pageSize, after: after);
      orders.addAll(result.orders);
      if (!result.hasNextPage) break;
      after = result.endCursor;
      if (after == null) break;
    }
    return orders;
  }

  Future<Map<String, dynamic>> _run(String document,
      {Map<String, dynamic>? variables}) async {
    final token = await auth.accessToken;
    if (token == null) {
      throw const ShopifyCustomerAccountException(
          ShopifyCustomerAccountFailure.notSignedIn, 'Not signed in');
    }
    var response = await _post(document, variables, token);
    if (response.statusCode == 401) {
      // The token may simply have been revoked early; one refresh and one
      // retry, then the rejection is reported. A refresh that comes back
      // with the same access token (no refresh token to use, or the grant
      // just wasn't renewed) would only repeat the same rejected request, so
      // the retry is skipped in that case.
      final refreshedTokens = await auth.refresh();
      if (refreshedTokens == null) {
        throw const ShopifyCustomerAccountException(
            ShopifyCustomerAccountFailure.notSignedIn,
            'Session expired; sign in again');
      }
      if (refreshedTokens.accessToken != token) {
        response =
            await _post(document, variables, refreshedTokens.accessToken);
      }
      if (response.statusCode == 401) {
        throw const ShopifyCustomerAccountException(
            ShopifyCustomerAccountFailure.apiError,
            'Customer Account API rejected the token');
      }
    }
    if (response.statusCode >= 500) {
      throw ShopifyCustomerAccountException(
          ShopifyCustomerAccountFailure.network,
          'Customer Account API returned ${response.statusCode}: '
          '${response.body}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ShopifyCustomerAccountException(
          ShopifyCustomerAccountFailure.apiError,
          'Customer Account API returned ${response.statusCode}: '
          '${response.body}');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const ShopifyCustomerAccountException(
          ShopifyCustomerAccountFailure.network,
          'Customer Account API returned invalid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ShopifyCustomerAccountException(
          ShopifyCustomerAccountFailure.network,
          'Customer Account API returned a non-object body');
    }
    final errors = decoded['errors'] as List?;
    if (errors != null && errors.isNotEmpty) {
      throw ShopifyCustomerAccountException(
          ShopifyCustomerAccountFailure.apiError,
          errors.map((e) => (e as Map)['message']).join(', '));
    }
    return (decoded['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<http.Response> _post(
      String document, Map<String, dynamic>? variables, String token) async {
    try {
      return await _client.post(
        endpoints.graphql,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': token,
        },
        body: jsonEncode({'query': document, 'variables': variables ?? {}}),
      );
    } catch (e) {
      // No verdict from Shopify, so the session is kept and the call can be
      // retried later.
      throw ShopifyCustomerAccountException(
          ShopifyCustomerAccountFailure.network, 'Request failed: $e');
    }
  }

  Address _addressFrom(Map<String, dynamic> data, String key) {
    final address = (data[key] as Map<String, dynamic>?)?['customerAddress'];
    if (address is! Map<String, dynamic>) {
      throw ShopifyCustomerAccountException(
          ShopifyCustomerAccountFailure.apiError, '$key returned no address');
    }
    return CustomerAccountMappers.address(address);
  }

  void _throwUserErrors(Map<String, dynamic> data, String key) {
    final errors = (data[key] as Map<String, dynamic>?)?['userErrors'] as List?;
    if (errors != null && errors.isNotEmpty) {
      throw ShopifyException(key, 'userErrors',
          errors: errors.map((e) => (e as Map)['message']).toList());
    }
  }
}
