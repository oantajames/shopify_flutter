/// GraphQL documents for the Customer Account API.
class CustomerAccountQueries {
  CustomerAccountQueries._();

  static const String _addressFields = r'''
    id
    address1
    address2
    city
    company
    country
    territoryCode
    province
    zoneCode
    zip
    firstName
    lastName
    name
    phoneNumber
    formattedArea
  ''';

  /// The signed-in customer's profile, default address and address book.
  static const String customer = '''
    query AppsCustomer {
      customer {
        id
        firstName
        lastName
        displayName
        imageUrl
        creationDate
        tags
        emailAddress { emailAddress }
        phoneNumber { phoneNumber }
        defaultAddress { $_addressFields }
        addresses(first: 20) { edges { node { $_addressFields } } }
      }
    }
  ''';

  /// Updates the customer's name.
  static const String customerUpdate = r'''
    mutation AppsCustomerUpdate($input: CustomerUpdateInput!) {
      customerUpdate(input: $input) {
        customer { id firstName lastName }
        userErrors { field message }
      }
    }
  ''';

  /// Adds an address to the customer's address book.
  static const String addressCreate = '''
    mutation AppsAddressCreate(\$address: CustomerAddressInput!, \$defaultAddress: Boolean) {
      customerAddressCreate(address: \$address, defaultAddress: \$defaultAddress) {
        customerAddress { $_addressFields }
        userErrors { field message }
      }
    }
  ''';

  /// Edits an address, and optionally makes it the default one.
  static const String addressUpdate = '''
    mutation AppsAddressUpdate(\$addressId: ID!, \$address: CustomerAddressInput, \$defaultAddress: Boolean) {
      customerAddressUpdate(addressId: \$addressId, address: \$address, defaultAddress: \$defaultAddress) {
        customerAddress { $_addressFields }
        userErrors { field message }
      }
    }
  ''';

  /// Removes an address from the customer's address book.
  static const String addressDelete = r'''
    mutation AppsAddressDelete($addressId: ID!) {
      customerAddressDelete(addressId: $addressId) {
        deletedAddressId
        userErrors { field message }
      }
    }
  ''';

  /// One page of the customer's orders, newest first.
  static const String orders = '''
    query AppsOrders(\$first: Int!, \$after: String) {
      customer {
        orders(first: \$first, after: \$after, sortKey: PROCESSED_AT, reverse: true) {
          pageInfo { hasNextPage endCursor }
          edges {
            cursor
            node {
              id
              name
              number
              email
              phone
              currencyCode
              processedAt
              cancelledAt
              cancelReason
              financialStatus
              fulfillmentStatus
              statusPageUrl
              totalPrice { amount currencyCode }
              subtotal { amount currencyCode }
              totalShipping { amount currencyCode }
              totalTax { amount currencyCode }
              totalRefunded { amount currencyCode }
              shippingAddress { $_addressFields }
              billingAddress { $_addressFields }
              fulfillments(first: 10) {
                edges { node { status trackingInformation { number url company } } }
              }
              lineItems(first: 100) {
                edges {
                  node {
                    id
                    title
                    variantTitle
                    quantity
                    price { amount currencyCode }
                    totalPrice { amount currencyCode }
                    totalDiscount { amount currencyCode }
                    requiresShipping
                    sku
                    variantId
                    productId
                    image { url altText }
                  }
                }
              }
            }
          }
        }
      }
    }
  ''';
}
