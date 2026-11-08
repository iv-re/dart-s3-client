import 'dart:async';
import 'package:mocktail/mocktail.dart';
import 'package:s3_client/s3_client.dart';
import 'package:test/test.dart';

class MockCredentialsProvider extends Mock implements S3CredentialsProvider {}

void main() {
  group('S3Credentials', () {
    test('can be created with valid credentials', () {
      const credentials = S3Credentials(
        accessKeyId: 'key',
        secretAccessKey: 'secret',
      );
      expect(credentials.accessKeyId, 'key');
      expect(credentials.secretAccessKey, 'secret');
      expect(credentials.sessionToken, isNull);
      expect(credentials.expires, isNull);
    });

    test('throws AssertionError when accessKeyId is empty', () {
      expect(
        () => S3Credentials(accessKeyId: '', secretAccessKey: 'secret'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws AssertionError when secretAccessKey is empty', () {
      expect(
        () => S3Credentials(accessKeyId: 'key', secretAccessKey: ''),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws AssertionError when sessionToken is empty', () {
      expect(
        () => S3Credentials(
          accessKeyId: 'key',
          secretAccessKey: 'secret',
          sessionToken: '',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('expired returns true if expires is in the past', () {
      final credentials = S3Credentials(
        accessKeyId: 'key',
        secretAccessKey: 'secret',
        sessionToken: 'token',
        expires: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(credentials.expired, isTrue);
    });

    test('expired returns false if expires is in the future', () {
      final credentials = S3Credentials(
        accessKeyId: 'key',
        secretAccessKey: 'secret',
        sessionToken: 'token',
        expires: DateTime.now().add(const Duration(minutes: 5)),
      );
      expect(credentials.expired, isFalse);
    });

    test('expired returns false if expires is null', () {
      const credentials = S3Credentials(
        accessKeyId: 'key',
        secretAccessKey: 'secret',
      );
      expect(credentials.expired, isFalse);
    });

    test(
      'throws AssertionError when expires is provided without sessionToken',
      () {
        expect(
          () => S3Credentials(
            accessKeyId: 'key',
            secretAccessKey: 'secret',
            expires: DateTime.now(),
          ),
          throwsA(isA<AssertionError>()),
        );
      },
    );

    test('can be created as anonymous credentials', () {
      const credentials = S3Credentials();
      expect(credentials.accessKeyId, isNull);
      expect(credentials.secretAccessKey, isNull);
      expect(credentials.isAnonymous, isTrue);
    });

    test('isAnonymous is false for non-anonymous credentials', () {
      const credentials = S3Credentials(
        accessKeyId: 'key',
        secretAccessKey: 'secret',
      );
      expect(credentials.isAnonymous, isFalse);
    });

    test('throws AssertionError when only accessKeyId is null', () {
      expect(
        () => S3Credentials(secretAccessKey: 'secret'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws AssertionError when only secretAccessKey is null', () {
      expect(
        () => S3Credentials(accessKeyId: 'key'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws AssertionError when only sessionToken is provided', () {
      expect(
        () => S3Credentials(sessionToken: 'token'),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('S3CredentialsProvider', () {
    test('static provider returns correct credentials', () async {
      final provider = S3CredentialsProvider.static(
        accessKeyId: 'key',
        secretAccessKey: 'secret',
      );
      final credentials = await provider.retrieve();
      expect(credentials.accessKeyId, 'key');
      expect(credentials.secretAccessKey, 'secret');
      expect(credentials.isAnonymous, isFalse);
    });

    test('anonymous provider returns anonymous credentials', () async {
      final provider = S3CredentialsProvider.anonymous();
      final credentials = await provider.retrieve();
      expect(credentials.accessKeyId, isNull);
      expect(credentials.secretAccessKey, isNull);
      expect(credentials.isAnonymous, isTrue);
    });

    test('cached provider caches credentials', () async {
      final inner = MockCredentialsProvider();
      const creds = S3Credentials(accessKeyId: 'key', secretAccessKey: 'sec');
      when(inner.retrieve).thenAnswer((_) => Future.value(creds));

      final cached = S3CredentialsProvider.cached(inner);

      final c1 = await cached.retrieve();
      final c2 = await cached.retrieve();

      expect(c1.accessKeyId, 'key');
      expect(c2.accessKeyId, 'key');
      verify(inner.retrieve).called(1);
    });

    test('cached provider deduplicates concurrent requests', () async {
      final completer = Completer<S3Credentials>();
      final inner = MockCredentialsProvider();
      when(inner.retrieve).thenAnswer((_) => completer.future);

      final cached = S3CredentialsProvider.cached(inner);

      final f1 = cached.retrieve();
      final f2 = cached.retrieve();

      completer.complete(
        const S3Credentials(accessKeyId: 'key', secretAccessKey: 'sec'),
      );

      final c1 = await f1;
      final c2 = await f2;

      expect(c1.accessKeyId, 'key');
      expect(c2.accessKeyId, 'key');
      verify(inner.retrieve).called(1);
    });

    test('cached provider refreshes near expiry', () async {
      final inner = MockCredentialsProvider();
      final creds = S3Credentials(
        accessKeyId: 'key',
        secretAccessKey: 'sec',
        sessionToken: 'tok',
        expires: DateTime.now().add(const Duration(seconds: 10)),
      );
      when(inner.retrieve).thenAnswer((_) => Future.value(creds));

      // Grace period is 20s. 10s remaining triggers refresh.
      final cached = S3CredentialsProvider.cached(
        inner,
        refreshGracePeriod: const Duration(seconds: 20),
      );

      await cached.retrieve();
      await cached.retrieve();

      verify(inner.retrieve).called(2);
    });

    test('cached provider reuses credentials that are not expiring', () async {
      final inner = MockCredentialsProvider();
      final creds = S3Credentials(
        accessKeyId: 'key',
        secretAccessKey: 'sec',
        sessionToken: 'tok',
        expires: DateTime.now().add(const Duration(hours: 1)),
      );
      when(inner.retrieve).thenAnswer((_) => Future.value(creds));

      final cached = S3CredentialsProvider.cached(inner);

      await cached.retrieve();
      await cached.retrieve();

      verify(inner.retrieve).called(1);
    });

    test('cached provider recovers after a synchronous failure', () async {
      final inner = MockCredentialsProvider();
      final cached = S3CredentialsProvider.cached(inner);

      when(inner.retrieve).thenThrow(StateError('transient'));
      await expectLater(Future.sync(cached.retrieve), throwsStateError);

      when(inner.retrieve).thenReturn(
        const S3Credentials(accessKeyId: 'key', secretAccessKey: 'secret'),
      );
      final credentials = await cached.retrieve();

      expect(credentials.accessKeyId, 'key');
    });

    test('cached provider invalidate clears cache', () async {
      final inner = MockCredentialsProvider();
      const creds = S3Credentials(accessKeyId: 'key', secretAccessKey: 'sec');
      when(inner.retrieve).thenAnswer((_) => Future.value(creds));

      final cached =
          S3CredentialsProvider.cached(inner) as S3CachedCredentialsProvider;

      await cached.retrieve();
      cached.invalidate();
      await cached.retrieve();

      verify(inner.retrieve).called(2);
    });
  });
}
