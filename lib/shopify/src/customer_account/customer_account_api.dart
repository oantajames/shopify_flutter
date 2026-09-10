import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shopify_flutter/mixins/src/shopify_error.dart';
import 'package:shopify_flutter/models/models.dart';

import 'customer_account_auth.dart';
import 'customer_account_endpoints.dart';
import 'customer_account_exception.dart';
import 'customer_account_mappers.dart';
import 'customer_account_queries.dart';

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
    return CustomerAccountMappers.address(data['customerAddressCreate']
        ['customerAddress'] as Map<String, dynamic>);
  }

  /// Edits the address identified by `address.id`.
  Future<Address> updateAddress(Address address, {bool? isDefault}) async {
    final data = await _run(CustomerAccountQueries.addressUpdate, variables: {
      'addressId': address.id,
      'address': CustomerAccountMappers.addressInput(address),
      if (isDefault != null) 'defaultAddress': isDefault,
    });
    _throwUserErrors(data, 'customerAddressUpdate');
    return CustomerAccountMappers.address(data['customerAddressUpdate']
        ['customerAddress'] as Map<String, dynamic>);
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

  /// All orders, newest first, following pagination.
  Future<List<Order>> getOrders({int pageSize = 50, int maxPages = 10}) async {
    final orders = <Order>[];
    String? after;
    for (var page = 0; page < maxPages; page++) {
      final data = await _run(CustomerAccountQueries.orders,
          variables: {'first': pageSize, 'after': after});
      final connection = data['customer']?['orders'] as Map<String, dynamic>?;
      if (connection == null) break;
      for (final edge in (connection['edges'] as List? ?? [])) {
        orders.add(CustomerAccountMappers.order(edge as Map<String, dynamic>));
      }
      final pageInfo = connection['pageInfo'] as Map<String, dynamic>?;
      if (pageInfo?['hasNextPage'] != true) break;
      after = pageInfo?['endCursor'] as String?;
      if (after == null) break;
    }
    return orders;
  }

  Future<Map<String, dynamic>> _run(String document,
      {Map<String, dynamic>? variables}) async {
    final token = await auth.accessToken;
    if (token == null) {
      throw const ShopifyCustomerAccountException(
          ShopifyCustomerAccountFailure.apiError, 'Not signed in');
    }
    final http.Response response;
    try {
      response = await _client.post(
        endpoints.graphql,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': token,
        },
        body: jsonEncode({'query': document, 'variables': variables ?? {}}),
      );
    } catch (e) {
      throw ShopifyCustomerAccountException(
          ShopifyCustomerAccountFailure.apiError, 'Request failed: $e');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ShopifyCustomerAccountException(
          ShopifyCustomerAccountFailure.apiError,
          'Customer Account API returned ${response.statusCode}: '
          '${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final errors = body['errors'] as List?;
    if (errors != null && errors.isNotEmpty) {
      throw ShopifyCustomerAccountException(
          ShopifyCustomerAccountFailure.apiError,
          errors.map((e) => (e as Map)['message']).join(', '));
    }
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  void _throwUserErrors(Map<String, dynamic> data, String key) {
    final errors = (data[key] as Map<String, dynamic>?)?['userErrors'] as List?;
    if (errors != null && errors.isNotEmpty) {
      throw ShopifyException(key, 'userErrors',
          errors: errors.map((e) => (e as Map)['message']).toList());
    }
  }
}
