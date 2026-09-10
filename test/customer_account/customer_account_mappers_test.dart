import 'package:flutter_test/flutter_test.dart';
import 'package:shopify_flutter/models/models.dart';
import 'package:shopify_flutter/shopify/src/customer_account/customer_account_mappers.dart';

void main() {
  test('maps a Customer Account customer onto ShopifyUser', () {
    final user = CustomerAccountMappers.customer({
      'id': 'gid://shopify/Customer/777',
      'firstName': 'Ana',
      'lastName': 'Pop',
      'displayName': 'Ana Pop',
      'emailAddress': {'emailAddress': 'ana@example.com'},
      'phoneNumber': {'phoneNumber': '+40700000000'},
      'creationDate': '2026-01-02T03:04:05Z',
      'tags': ['vip'],
      'defaultAddress': {
        'id': 'gid://shopify/CustomerAddress/1',
        'address1': 'Str. Lunga 1',
        'city': 'Cluj',
        'country': 'Romania',
        'territoryCode': 'RO',
        'province': 'Cluj',
        'zoneCode': 'CJ',
        'zip': '400000',
        'firstName': 'Ana',
        'lastName': 'Pop',
        'name': 'Ana Pop',
        'phoneNumber': '+40700000000',
        'formattedArea': 'Cluj, Romania',
      },
      'addresses': {
        'edges': [
          {
            'node': {
              'id': 'gid://shopify/CustomerAddress/1',
              'address1': 'Str. Lunga 1',
              'city': 'Cluj',
              'country': 'Romania',
              'territoryCode': 'RO',
              'zoneCode': 'CJ',
              'zip': '400000',
            }
          }
        ]
      },
    });
    expect(user.id, 'gid://shopify/Customer/777');
    expect(user.email, 'ana@example.com');
    expect(user.phone, '+40700000000');
    expect(user.createdAt, '2026-01-02T03:04:05Z');
    expect(user.tags, ['vip']);
    expect(user.defaultAddress!.countryCode, 'RO');
    expect(user.defaultAddress!.provinceCode, 'CJ');
    expect(user.defaultAddress!.phone, '+40700000000');
    expect(
        user.address!.addressList.single.id, 'gid://shopify/CustomerAddress/1');
  });

  test('maps an Address onto CustomerAddressInput', () {
    final input = CustomerAccountMappers.addressInput(Address(
      address1: 'Str. Lunga 1',
      address2: 'Ap. 2',
      city: 'Cluj',
      company: 'ACME',
      countryCode: 'RO',
      country: 'Romania',
      firstName: 'Ana',
      lastName: 'Pop',
      phone: '+40700000000',
      provinceCode: 'CJ',
      province: 'Cluj',
      zip: '400000',
    ));
    expect(input, {
      'address1': 'Str. Lunga 1',
      'address2': 'Ap. 2',
      'city': 'Cluj',
      'company': 'ACME',
      'territoryCode': 'RO',
      'firstName': 'Ana',
      'lastName': 'Pop',
      'phoneNumber': '+40700000000',
      'zoneCode': 'CJ',
      'zip': '400000',
    });
  });

  test('maps a Customer Account order onto Order', () {
    final order = CustomerAccountMappers.order({
      'cursor': 'c1',
      'node': {
        'id': 'gid://shopify/Order/1?key=abc',
        'name': '#1001',
        'number': 1001,
        'email': 'ana@example.com',
        'phone': null,
        'currencyCode': 'RON',
        'processedAt': '2026-02-01T10:00:00Z',
        'cancelledAt': null,
        'cancelReason': null,
        'financialStatus': 'PAID',
        'fulfillmentStatus': 'UNFULFILLED',
        'statusPageUrl': 'https://demo.myshopify.com/orders/abc',
        'totalPrice': {'amount': '120.0', 'currencyCode': 'RON'},
        'subtotal': {'amount': '100.0', 'currencyCode': 'RON'},
        'totalShipping': {'amount': '20.0', 'currencyCode': 'RON'},
        'totalTax': {'amount': '0.0', 'currencyCode': 'RON'},
        'totalRefunded': {'amount': '0.0', 'currencyCode': 'RON'},
        'shippingAddress': {
          'id': 'gid://shopify/CustomerAddress/1',
          'name': 'Ana Pop',
          'firstName': 'Ana',
          'lastName': 'Pop',
          'address1': 'Str. Lunga 1',
          'city': 'Cluj',
          'country': 'Romania',
          'territoryCode': 'RO',
          'zoneCode': 'CJ',
          'province': 'Cluj',
          'zip': '400000',
          'phoneNumber': '+40700000000',
        },
        'billingAddress': null,
        'fulfillments': {
          'edges': [
            {
              'node': {
                'status': 'SUCCESS',
                'trackingInformation': [
                  {
                    'number': 'TRK1',
                    'url': 'https://t.example/TRK1',
                    'company': 'DHL'
                  }
                ]
              }
            }
          ]
        },
        'lineItems': {
          'edges': [
            {
              'node': {
                'id': 'gid://shopify/LineItem/1',
                'title': 'Coffee',
                'variantTitle': '250g',
                'quantity': 2,
                'price': {'amount': '50.0', 'currencyCode': 'RON'},
                'totalPrice': {'amount': '90.0', 'currencyCode': 'RON'},
                'totalDiscount': {'amount': '10.0', 'currencyCode': 'RON'},
                'requiresShipping': true,
                'sku': 'CF-250',
                'variantId': 'gid://shopify/ProductVariant/9',
                'productId': 'gid://shopify/Product/8',
                'image': {'url': 'https://cdn/img.png', 'altText': 'Coffee'},
              }
            }
          ]
        },
      }
    });
    expect(order.id, 'gid://shopify/Order/1?key=abc');
    expect(order.orderNumber, 1001);
    expect(order.name, '#1001');
    expect(order.statusUrl, 'https://demo.myshopify.com/orders/abc');
    expect(order.totalPriceV2.amount, 120.0);
    expect(order.subtotalPriceV2.amount, 100.0);
    expect(order.totalShippingPriceV2.amount, 20.0);
    expect(order.cursor, 'c1');
    expect(order.shippingAddress!.address1, 'Str. Lunga 1');
    expect(order.shippingAddress!.countryCodeV2, 'RO');
    expect(order.shippingAddress!.phone, '+40700000000');
    expect(order.billingAddress, isNull);
    final line = order.lineItems.lineItemOrderList.single;
    expect(line.title, 'Coffee');
    expect(line.quantity, 2);
    expect(line.currentQuantity, 2);
    expect(line.originalTotalPrice.amount, 100.0);
    expect(line.discountedTotalPrice.amount, 90.0);
    expect(line.discountAllocations.single.allocatedAmount!.amount, 10.0);
    expect(line.variant!.title, '250g');
    expect(line.variant!.image!.originalSrc, 'https://cdn/img.png');
    expect(order.successfulFulfillments!.single.trackingCompany, 'DHL');
    expect(order.successfulFulfillments!.single.trackingInfo!.single.number,
        'TRK1');
  });

  test('maps a sparse order node without throwing', () {
    final order = CustomerAccountMappers.order({
      'node': {'id': 'gid://shopify/Order/2'}
    });
    expect(order.id, 'gid://shopify/Order/2');
    expect(order.orderNumber, 0);
    expect(order.totalPriceV2.amount, 0);
    expect(order.subtotalPriceV2.amount, 0);
    expect(order.totalShippingPriceV2.amount, 0);
    expect(order.totalTaxV2.amount, 0);
    expect(order.lineItems.lineItemOrderList, isEmpty);
    expect(order.successfulFulfillments, isEmpty);
    expect(order.shippingAddress, isNull);
    expect(order.cursor, isNull);
  });

  test('a line item without a discount keeps the reported total', () {
    final order = CustomerAccountMappers.order({
      'node': {
        'id': 'gid://shopify/Order/3',
        'currencyCode': 'RON',
        'lineItems': {
          'edges': [
            {
              'node': {
                'id': 'gid://shopify/LineItem/1',
                'title': 'Coffee',
                'quantity': 2,
                'price': {'amount': '50.0', 'currencyCode': 'RON'},
                'totalPrice': {'amount': '95.0', 'currencyCode': 'RON'},
              }
            }
          ]
        },
      }
    });
    final line = order.lineItems.lineItemOrderList.single;
    expect(line.originalTotalPrice.amount, 100.0);
    expect(line.discountedTotalPrice.amount, 95.0);
    expect(line.discountAllocations, isEmpty);
  });
}
