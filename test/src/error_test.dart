import 'package:s3_client/s3_client.dart';
import 'package:test/test.dart';

void main() {
  group('S3Exception', () {
    test('creates correct subclass from S3Error', () {
      const error = S3Error(
        code: 'AccessDenied',
        message: 'Access was denied.',
      );
      final exc = S3Exception.fromError(error);
      expect(exc, isA<S3AccessDeniedException>());
      expect(exc.code, equals('AccessDenied'));
      expect(exc.message, equals('Access was denied.'));
    });

    test('creates correct subclass from code', () {
      final exc = S3Exception.fromCode('AccessDenied', 'Access was denied.');
      expect(exc, isA<S3AccessDeniedException>());
      expect(exc.code, equals('AccessDenied'));
      expect(exc.message, equals('Access was denied.'));
      expect(exc.toString(), contains('S3AccessDeniedException'));
    });

    test('creates correct subclass for NoSuchKey', () {
      final exc = S3Exception.fromCode(
        'NoSuchKey',
        'The specified key does not exist.',
      );
      expect(exc, isA<S3NoSuchKeyException>());
      expect(exc.code, equals('NoSuchKey'));
      expect(exc.message, equals('The specified key does not exist.'));
    });

    test('falls back to S3UnknownException for unmapped code', () {
      final exc = S3Exception.fromCode('SomeNewError', 'A new error occurred.');
      expect(exc, isA<S3UnknownException>());
      expect(exc.code, equals('SomeNewError'));
      expect(exc.message, equals('A new error occurred.'));
    });
  });
}
