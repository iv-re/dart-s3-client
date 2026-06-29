import 'dart:async';
import 'package:clock/clock.dart';

/// AWS credentials used to sign S3 requests.
class S3Credentials {
  /// Can represent temporary credentials (if [sessionToken] is set) or
  /// anonymous credentials (if keys are null).
  const S3Credentials({
    this.accessKeyId,
    this.secretAccessKey,
    this.sessionToken,
    this.expires,
  }) : assert(
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

  /// AWS Access Key ID. Null for anonymous access.
  final String? accessKeyId;

  /// AWS Secret Access Key. Null for anonymous access.
  final String? secretAccessKey;

  /// Temporary AWS Session Token (for STS).
  final String? sessionToken;

  /// Expiry time of temporary credentials.
  final DateTime? expires;

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

class S3StaticCredentialsProvider implements S3CredentialsProvider {
  S3StaticCredentialsProvider({
    String? accessKeyId,
    String? secretAccessKey,
    String? sessionToken,
  }) : _value = S3Credentials(
         accessKeyId: accessKeyId,
         secretAccessKey: secretAccessKey,
         sessionToken: sessionToken,
       );

  final S3Credentials _value;

  @override
  FutureOr<S3Credentials> retrieve() {
    return _value;
  }
}

class S3AnonymousCredentialsProvider implements S3CredentialsProvider {
  const S3AnonymousCredentialsProvider();

  @override
  FutureOr<S3Credentials> retrieve() {
    return const S3Credentials();
  }
}

/// Caching provider that wraps and caches another [S3CredentialsProvider].
class S3CachedCredentialsProvider implements S3CredentialsProvider {
  S3CachedCredentialsProvider(
    this._provider, {
    this.refreshGracePeriod = const Duration(seconds: 15),
  });

  final S3CredentialsProvider _provider;

  /// Time buffer before expiration to trigger early refresh.
  final Duration refreshGracePeriod;

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

    return _retrieveFuture ??= _retrieveAndCache();
  }

  FutureOr<S3Credentials> _retrieveAndCache() async {
    try {
      final credentials = await _provider.retrieve();
      _cached = credentials;
      return credentials;
    } finally {
      _retrieveFuture = null;
    }
  }

  /// Invalidate cache.
  void invalidate() {
    _cached = null;
  }
}
