import 'package:shopify_flutter/models/models.dart';

/// Converts Customer Account API JSON into the package's existing models so
/// consumers keep a single shape regardless of which API served the data.
class CustomerAccountMappers {
  CustomerAccountMappers._();

  /// `customer { ... }` → [ShopifyUser].
  static ShopifyUser customer(Map<String, dynamic> json) {
    final addresses = (json['addresses']?['edges'] as List?)
            ?.map((e) => address((e as Map)['node'] as Map<String, dynamic>))
            .toList() ??
        <Address>[];
    return ShopifyUser(
      id: json['id'] as String?,
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
      displayName: json['displayName'] as String?,
      email: json['emailAddress']?['emailAddress'] as String?,
      phone: json['phoneNumber']?['phoneNumber'] as String?,
      createdAt: json['creationDate'] as String?,
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      defaultAddress: json['defaultAddress'] == null
          ? null
          : address(json['defaultAddress'] as Map<String, dynamic>),
      address: Addresses(addressList: addresses),
    );
  }

  /// `CustomerAddress` → [Address].
  static Address address(Map<String, dynamic> json) => Address(
        id: json['id'] as String?,
        address1: json['address1'] as String?,
        address2: json['address2'] as String?,
        city: json['city'] as String?,
        company: json['company'] as String?,
        country: json['country'] as String?,
        countryCode: json['territoryCode'] as String?,
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        formattedArea: json['formattedArea'] as String?,
        name: json['name'] as String?,
        phone: json['phoneNumber'] as String?,
        province: json['province'] as String?,
        provinceCode: json['zoneCode'] as String?,
        zip: json['zip'] as String?,
      );

  /// [Address] → `CustomerAddressInput`. Null fields are omitted.
  static Map<String, dynamic> addressInput(Address a) => {
        if (a.address1 != null) 'address1': a.address1,
        if (a.address2 != null) 'address2': a.address2,
        if (a.city != null) 'city': a.city,
        if (a.company != null) 'company': a.company,
        if (a.countryCode != null) 'territoryCode': a.countryCode,
        if (a.firstName != null) 'firstName': a.firstName,
        if (a.lastName != null) 'lastName': a.lastName,
        if (a.phone != null) 'phoneNumber': a.phone,
        if (a.provinceCode != null) 'zoneCode': a.provinceCode,
        if (a.zip != null) 'zip': a.zip,
      };

  /// One `orders.edges[i]` → [Order], via the Storefront-shaped JSON that
  /// [Order.fromGraphJson] already understands.
  static Order order(Map<String, dynamic> edge) {
    final node = edge['node'] as Map<String, dynamic>;
    Map<String, dynamic> money(dynamic m) => {
          'amount': (m?['amount'] ?? '0').toString(),
          'currencyCode': m?['currencyCode'] ?? node['currencyCode'] ?? '',
        };
    Map<String, dynamic>? shippingAddress(dynamic a) {
      if (a == null) return null;
      final m = a as Map<String, dynamic>;
      return {
        'name': m['name'] ??
            '${m['firstName'] ?? ''} ${m['lastName'] ?? ''}'.trim(),
        'id': m['id'] ?? '',
        'lastName': m['lastName'] ?? '',
        'firstName': m['firstName'],
        'address1': m['address1'] ?? '',
        'address2': m['address2'],
        'city': m['city'] ?? '',
        'company': m['company'],
        'country': m['country'] ?? '',
        'countryCodeV2': m['territoryCode'],
        'phone': m['phoneNumber'],
        'province': m['province'],
        'provinceCode': m['zoneCode'],
        'zip': m['zip'],
      };
    }

    final lineItems = ((node['lineItems']?['edges'] as List?) ?? []).map((e) {
      final li = (e as Map)['node'] as Map<String, dynamic>;
      final quantity = (li['quantity'] as num?)?.toInt() ?? 0;
      final unit = double.tryParse(money(li['price'])['amount'] as String) ?? 0;
      final total = money(li['totalPrice']);
      final discount = li['totalDiscount'];
      final currency = money(li['price'])['currencyCode'];
      final image = li['image'];
      return {
        'node': {
          'currentQuantity': quantity,
          'quantity': quantity,
          'title': li['title'] ?? '',
          'originalTotalPrice': {
            'amount': (unit * quantity).toString(),
            'currencyCode': currency,
          },
          'discountedTotalPrice': total,
          'discountAllocations': [
            if (discount != null &&
                (double.tryParse(discount['amount'].toString()) ?? 0) > 0)
              {'allocatedAmount': money(discount)},
          ],
          'variant': {
            'id': li['variantId'] ?? li['id'] ?? '',
            'title': li['variantTitle'] ?? li['title'] ?? '',
            'availableForSale': true,
            'requiresShipping': li['requiresShipping'] ?? true,
            'sku': li['sku'],
            'priceV2': money(li['price']),
            if (image != null)
              'image': {
                'originalSrc': image['url'],
                'id': image['url'],
                'altText': image['altText'],
              },
          },
        }
      };
    }).toList();

    final fulfillments = ((node['fulfillments']?['edges'] as List?) ?? [])
        .map((e) => (e as Map)['node'] as Map<String, dynamic>)
        .where((f) => f['status'] == 'SUCCESS')
        .map((f) {
      final tracking = (f['trackingInformation'] as List?) ?? [];
      return {
        'trackingCompany':
            tracking.isNotEmpty ? (tracking.first as Map)['company'] : null,
        'trackingInfo': tracking
            .map((t) => {'number': (t as Map)['number'], 'url': t['url']})
            .toList(),
      };
    }).toList();

    return Order.fromGraphJson({
      'cursor': edge['cursor'],
      'node': {
        'id': node['id'],
        'email': node['email'] ?? '',
        'currencyCode': node['currencyCode'] ?? '',
        'customerUrl': node['statusPageUrl'] ?? '',
        'lineItems': {'edges': lineItems},
        'name': node['name'] ?? '',
        'orderNumber': (node['number'] as num?)?.toInt() ?? 0,
        'phone': node['phone'],
        'processedAt': node['processedAt'] ?? '',
        'financialStatus': node['financialStatus'] ?? '',
        'fulfillmentStatus': node['fulfillmentStatus'] ?? '',
        'shippingAddress': shippingAddress(node['shippingAddress']),
        'billingAddress': shippingAddress(node['billingAddress']),
        'statusUrl': node['statusPageUrl'] ?? '',
        'subtotalPriceV2': money(node['subtotal']),
        'totalPriceV2': money(node['totalPrice']),
        'totalRefundedV2': money(node['totalRefunded']),
        'totalShippingPriceV2': money(node['totalShipping']),
        'totalTaxV2': money(node['totalTax']),
        'canceledAt': node['cancelledAt'],
        'cancelReason': node['cancelReason'],
        'successfulFulfillments': fulfillments,
      },
    });
  }
}
