import 'dart:async';
import 'package:clock/clock.dart';
import 'package:mocktail/mocktail.dart';
import 'package:s3_client/s3_client.dart';
import 'package:s3_client/src/request.dart';
import 'package:s3_client/src/sign/signer.dart';
import 'package:test/test.dart';

class MockCredentialsProvider extends Mock implements S3CredentialsProvider {}

void main() {
  group('S3Signer', () {
    late MockCredentialsProvider mockCredentialsProvider;
    late S3Signer signer;

    const region = 'us-west-2';
    final fixedTime = DateTime.utc(2013, 5, 24, 15);

    setUp(() {
      mockCredentialsProvider = MockCredentialsProvider();
      signer = S3Signer(
        credentialsProvider: mockCredentialsProvider,
        region: region,
      );
    });

    void testWithClock(String name, FutureOr<void> Function() body) {
      test(name, () => withClock(Clock.fixed(fixedTime), body));
    }

    test(
      'does not modify request with anonymous credentials',
      () async {
        const credentials = S3Credentials();
        when(
          mockCredentialsProvider.retrieve,
        ).thenAnswer((_) => Future.value(credentials));
        final req = S3Request(
          'GET',
          Uri.parse('https://example-bucket.s3.amazonaws.com/object.txt'),
        );
        final originalHeaders = Map<String, String>.from(req.headers);

        await signer.sign(req);

        expect(req.headers, originalHeaders);
      },
    );

    test(
      'returns original URL unmodified when credentials are anonymous',
      () async {
        const credentials = S3Credentials();
        when(
          mockCredentialsProvider.retrieve,
        ).thenAnswer((_) => Future.value(credentials));
        final url = Uri.parse(
          'https://example-bucket.s3.amazonaws.com/object.txt',
        );

        final presigned = await signer.presign('GET', url);

        expect(presigned, url);
      },
    );

    testWithClock(
      'signs basic GET request correctly',
      () async {
        const credentials = S3Credentials(
          accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
          secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        );
        when(
          mockCredentialsProvider.retrieve,
        ).thenAnswer((_) => Future.value(credentials));
        final req = S3Request(
          'GET',
          Uri.parse('https://example-bucket.s3.amazonaws.com/object.txt'),
        );

        await signer.sign(req);

        expect(req.headers['host'], 'example-bucket.s3.amazonaws.com');
        expect(req.headers['x-amz-date'], '20130524T150000Z');
        expect(
          req.headers['x-amz-content-sha256'],
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        );
        expect(
          req.headers['authorization'],
          'AWS4-HMAC-SHA256 '
          'Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-west-2/s3/aws4_request, '
          'SignedHeaders=host;x-amz-content-sha256;x-amz-date, '
          'Signature='
          'ba4abcec53211029009e65a8c29eaa77765c7504532babc054794b4642727e1b',
        );
      },
    );

    testWithClock(
      'adds and signs session token when provided',
      () async {
        const credentials = S3Credentials(
          accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
          secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
          sessionToken: 'test-session-token',
        );
        when(
          mockCredentialsProvider.retrieve,
        ).thenAnswer((_) => Future.value(credentials));
        final req = S3Request('GET', Uri.parse('https://example.com/'));

        await signer.sign(req);

        expect(req.headers['x-amz-security-token'], 'test-session-token');
        expect(
          req.headers['authorization'],
          'AWS4-HMAC-SHA256 '
          'Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-west-2/s3/aws4_request, '
          'SignedHeaders=host;x-amz-content-sha256;x-amz-date;'
          'x-amz-security-token, '
          'Signature='
          'fec5caed8935aaa4ce61c55121d611911a4840d8ddffeeb222223575defab2e9',
        );
      },
    );

    testWithClock(
      'computes SHA256 payload hash of request body bytes',
      () async {
        const credentials = S3Credentials(
          accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
          secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        );
        when(
          mockCredentialsProvider.retrieve,
        ).thenAnswer((_) => Future.value(credentials));
        final req = S3Request('POST', Uri.parse('https://example.com/'))
          ..body = 'hello world';

        await signer.sign(req);

        expect(
          req.headers['x-amz-content-sha256'],
          'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9',
        );
        expect(
          req.headers['authorization'],
          'AWS4-HMAC-SHA256 '
          'Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-west-2/s3/aws4_request, '
          'SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, '
          'Signature='
          'ed30d84839a300a15327baff3ffd96fee11e1f6bb2b82063abceb836988627de',
        );
      },
    );

    test(
      'respects existing x-amz-content-sha256 header',
      () async {
        const credentials = S3Credentials(
          accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
          secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        );
        when(
          mockCredentialsProvider.retrieve,
        ).thenAnswer((_) => Future.value(credentials));
        final req = S3Request('PUT', Uri.parse('https://example.com/'));
        req.headers['x-amz-content-sha256'] = 'UNSIGNED-PAYLOAD';

        await signer.sign(req);

        expect(req.headers['x-amz-content-sha256'], 'UNSIGNED-PAYLOAD');
      },
    );

    testWithClock(
      'presigns URL correctly',
      () async {
        const credentials = S3Credentials(
          accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
          secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        );
        when(
          mockCredentialsProvider.retrieve,
        ).thenAnswer((_) => Future.value(credentials));
        final url = Uri.parse(
          'https://example-bucket.s3.amazonaws.com/object.txt',
        );

        final presigned = await signer.presign(
          'GET',
          url,
          expires: const Duration(hours: 1),
        );

        expect(
          presigned.queryParameters['X-Amz-Algorithm'],
          'AWS4-HMAC-SHA256',
        );
        expect(presigned.queryParameters['X-Amz-Expires'], '3600');
        expect(presigned.queryParameters['X-Amz-SignedHeaders'], 'host');
        expect(
          presigned.queryParameters['X-Amz-Credential'],
          'AKIAIOSFODNN7EXAMPLE/20130524/us-west-2/s3/aws4_request',
        );
        expect(presigned.queryParameters['X-Amz-Date'], '20130524T150000Z');
        expect(
          presigned.queryParameters['X-Amz-Signature'],
          '937d6776aa1a6e1a66cdf604c1b57db779298d0a723a6b7e06e99d06d9240110',
        );
      },
    );

    test(
      'presign includes security token when provided',
      () async {
        const credentials = S3Credentials(
          accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
          secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
          sessionToken: 'test-session-token',
        );
        when(
          mockCredentialsProvider.retrieve,
        ).thenAnswer((_) => Future.value(credentials));
        final url = Uri.parse(
          'https://example-bucket.s3.amazonaws.com/object.txt',
        );

        final presigned = await signer.presign('GET', url);

        expect(
          presigned.queryParameters['X-Amz-Security-Token'],
          'test-session-token',
        );
      },
    );

    test(
      'uses UNSIGNED-PAYLOAD for S3StreamedRequest',
      () async {
        const credentials = S3Credentials(
          accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
          secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        );
        when(
          mockCredentialsProvider.retrieve,
        ).thenAnswer((_) => Future.value(credentials));
        final req = S3StreamedRequest(
          'POST',
          Uri.parse('https://example.com/'),
        );

        await signer.sign(req);

        expect(req.headers['x-amz-content-sha256'], 'UNSIGNED-PAYLOAD');
      },
    );

    test(
      'respects case-insensitive x-amz-content-sha256 header',
      () async {
        const credentials = S3Credentials(
          accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
          secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        );
        when(
          mockCredentialsProvider.retrieve,
        ).thenAnswer((_) => Future.value(credentials));
        final req = S3Request('PUT', Uri.parse('https://example.com/'));
        req.headers['X-Amz-Content-Sha256'] = 'CUSTOM-HASH';

        await signer.sign(req);

        expect(req.headers['x-amz-content-sha256'], 'CUSTOM-HASH');
      },
    );
  });
}
