import 'dart:async';
import 'package:clock/clock.dart';

/// AWS credentials used to sign S3 requests.
///
/// Can represent temporary credentials (if [sessionToken] is set) or
/// anonymous credentials (if keys are null).
class const S3Credentials({
  /// AWS Access Key ID. Null for anonymous access.
  final String? accessKeyId,

  /// AWS Secret Access Key. Null for anonymous access.
  final String? secretAccessKey,

  /// Temporary AWS Session Token (for STS).
  final String? sessionToken,

  /// Expiry time of temporary credentials.
  final DateTime? expires,
}) {
  this : assert(
         (accessKeyId == null) == (secretAccessKey == null),
         'accessKeyId and secretAccessKey must be provided together '
         '(or both be null).',
       ),
       assert(
         accessKeyId == null || accessKeyId != '',
         'accessKeyId cannot be an empty string.',
       ),
       assert(
         secretAccessKey == null || secretAccessKey != '',
         'secretAccessKey cannot be an empty string.',
       ),
       assert(
         sessionToken == null || sessionToken != '',
         'sessionToken cannot be an empty string.',
       ),
       assert(
         sessionToken == null || accessKeyId != null,
         'sessionToken cannot be used without providing '
         'accessKeyId and secretAccessKey.',
       ),
       assert(
         expires == null || sessionToken != null,
         'expires should only be provided along with a temporary sessionToken.',
       );

  /// Whether these credentials are anonymous (unsigned requests).
  bool get isAnonymous {
    return accessKeyId == null;
  }

  /// Whether temporary credentials have expired.
  bool get expired {
    return expires?.isBefore(clock.now()) ?? false;
  }
}

/// Provider interface for retrieving S3 credentials.
abstract interface class S3CredentialsProvider {
  /// Creates a static credentials provider.
  factory S3CredentialsProvider.static({
    String? accessKeyId,
    String? secretAccessKey,
    String? sessionToken,
  }) = S3StaticCredentialsProvider;

  /// Creates an anonymous credentials provider.
  factory S3CredentialsProvider.anonymous() = S3AnonymousCredentialsProvider;

  /// Creates a caching provider that wraps and caches another [provider].
  factory S3CredentialsProvider.cached(
    S3CredentialsProvider provider, {
    Duration refreshGracePeriod,
  }) = S3CachedCredentialsProvider;

  FutureOr<S3Credentials> retrieve();
}

class S3StaticCredentialsProvider({
  String? accessKeyId,
  String? secretAccessKey,
  String? sessionToken,
}) implements S3CredentialsProvider {
  final S3Credentials _value = S3Credentials(
    accessKeyId: accessKeyId,
    secretAccessKey: secretAccessKey,
    sessionToken: sessionToken,
  );

  @override
  FutureOr<S3Credentials> retrieve() {
    return _value;
  }
}

class const S3AnonymousCredentialsProvider() implements S3CredentialsProvider {
  @override
  FutureOr<S3Credentials> retrieve() {
    return const S3Credentials();
  }
}

/// Caching provider that wraps and caches another [S3CredentialsProvider].
class S3CachedCredentialsProvider(
  final S3CredentialsProvider _provider, {
  /// Time buffer before expiration to trigger early refresh.
  final Duration refreshGracePeriod = const Duration(seconds: 15),
}) implements S3CredentialsProvider {
  S3Credentials? _cached;
  FutureOr<S3Credentials>? _retrieveFuture;

  @override
  FutureOr<S3Credentials> retrieve() {
    final cached = _cached;
    if (cached != null) {
      final expires = cached.expires;
      if (expires == null) {
        return cached;
      }

      if (expires.isAfter(clock.now().add(refreshGracePeriod))) {
        return cached;
      }
    }

    // Cleared in `whenComplete` so that it always runs after this assignment,
    // even if the provider throws synchronously.
    return _retrieveFuture ??= _retrieveAndCache().whenComplete(() {
      _retrieveFuture = null;
    });
  }

  Future<S3Credentials> _retrieveAndCache() async {
    final credentials = await _provider.retrieve();
    _cached = credentials;
    return credentials;
  }

  /// Invalidate cache.
  void invalidate() {
    _cached = null;
  }
}
