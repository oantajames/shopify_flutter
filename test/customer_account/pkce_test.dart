import 'package:flutter_test/flutter_test.dart';
import 'package:shopify_flutter/shopify/src/customer_account/pkce.dart';

void main() {
  test('challenge matches RFC 7636 appendix B vector', () {
    const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
    expect(Pkce.challengeFor(verifier),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
  });

  test('generated verifier is 128 chars from the allowed charset', () {
    final pkce = Pkce.generate();
    expect(pkce.verifier.length, 128);
    expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(pkce.verifier), isTrue);
    expect(pkce.challenge, Pkce.challengeFor(pkce.verifier));
    expect(pkce.challenge.contains('='), isFalse);
  });

  test('state and nonce are url-safe and unique', () {
    final a = Pkce.randomToken();
    final b = Pkce.randomToken();
    expect(a, isNot(b));
    expect(RegExp(r'^[A-Za-z0-9\-_]+$').hasMatch(a), isTrue);
  });
}
