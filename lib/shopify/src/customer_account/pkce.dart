// Verifier/challenge generation adapted from package:oauth2
// (Copyright (c) 2012, the Dart project authors. BSD-style license,
// https://github.com/dart-lang/oauth2/blob/master/LICENSE).
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE code verifier + S256 challenge (RFC 7636).
class Pkce {
  /// The random code verifier sent to the token endpoint.
  final String verifier;

  /// The S256 challenge sent to the authorize endpoint.
  final String challenge;

  const Pkce._(this.verifier, this.challenge);

  static const String _charset =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// Generates a fresh 128-character verifier and its challenge.
  static Pkce generate() {
    final random = Random.secure();
    final verifier = List.generate(
      128,
      (_) => _charset[random.nextInt(_charset.length)],
    ).join();
    return Pkce._(verifier, challengeFor(verifier));
  }

  /// base64url(sha256(verifier)) without padding.
  static String challengeFor(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  /// URL-safe random token for `state` / `nonce`.
  static String randomToken([int bytes = 32]) {
    final random = Random.secure();
    final data = List<int>.generate(bytes, (_) => random.nextInt(256));
    return base64Url.encode(data).replaceAll('=', '');
  }
}
