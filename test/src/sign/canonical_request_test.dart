import 'package:s3_client/src/sign/canonical_request.dart';
import 'package:test/test.dart';

void main() {
  group('CanonicalRequest', () {
    test('formats basic GET request correctly', () {
      final req = CanonicalRequest(
        method: 'GET',
        url: Uri.parse('https://example-bucket.s3.amazonaws.com/object.txt'),
        queryParameters: {},
        headers: {
          'Host': 'example-bucket.s3.amazonaws.com',
          'X-Amz-Date': '20130524T150000Z',
        },
        payloadHash:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );

      expect(req.signedHeaders, 'host;x-amz-date');
      expect(
        req.canonicalHeaders,
        'host:example-bucket.s3.amazonaws.com\n'
        'x-amz-date:20130524T150000Z\n',
      );
      expect(
        req.toString(),
        'GET\n'
        '/object.txt\n'
        '\n'
        'host:example-bucket.s3.amazonaws.com\n'
        'x-amz-date:20130524T150000Z\n'
        '\n'
        'host;x-amz-date\n'
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('collapses whitespaces in headers and ignores user-agent', () {
      final req = CanonicalRequest(
        method: 'GET',
        url: Uri.parse('https://example.com/'),
        queryParameters: {},
        headers: {
          'Host': 'example.com',
          'User-Agent': 'ignored-agent',
          'X-Amz-Custom': '  some    value   with   spaces  ',
        },
        payloadHash: 'UNSIGNED-PAYLOAD',
      );

      expect(req.signedHeaders, 'host;x-amz-custom');
      expect(
        req.canonicalHeaders,
        'host:example.com\n'
        'x-amz-custom:some value with spaces\n',
      );
    });

    test('canonicalizes and encodes query parameters correctly', () {
      final req = CanonicalRequest(
        method: 'GET',
        url: Uri.parse(
          "https://example.com/path?z=1&a=value with spaces&z=2&b=*!'()",
        ),
        queryParameters: {
          'z': ['1', '2'],
          'a': ['value with spaces'],
          'b': ["*!'()"],
        },
        headers: {'Host': 'example.com'},
        payloadHash: 'UNSIGNED-PAYLOAD',
      );

      expect(
        req.toString().split('\n')[2], // canonical query string index
        'a=value%20with%20spaces&b=%2A%21%27%28%29&z=1&z=2',
      );
    });

    test('canonicalizes empty path to slash', () {
      final req = CanonicalRequest(
        method: 'GET',
        url: Uri.parse('https://example.com'),
        queryParameters: {},
        headers: {'Host': 'example.com'},
        payloadHash: 'UNSIGNED-PAYLOAD',
      );

      expect(
        req.toString().split('\n')[1], // canonical URI index
        '/',
      );
    });

    test('sorts query parameter values for the same key', () {
      final req = CanonicalRequest(
        method: 'GET',
        url: Uri.parse('https://example.com/path?z=2&z=1'),
        queryParameters: {
          'z': ['2', '1'],
        },
        headers: {'Host': 'example.com'},
        payloadHash: 'UNSIGNED-PAYLOAD',
      );

      expect(
        req.toString().split('\n')[2], // canonical query string index
        'z=1&z=2',
      );
    });

    test('does not double-encode already percent-encoded values', () {
      final url = Uri.parse('https://example.com/path?key=%2Fvalue');
      final req = CanonicalRequest(
        method: 'GET',
        url: url,
        queryParameters: url.queryParametersAll,
        headers: {'Host': 'example.com'},
        payloadHash: 'UNSIGNED-PAYLOAD',
      );

      expect(
        req.toString().split('\n')[2], // canonical query string index
        'key=%2Fvalue',
      );
    });

    test('canonicalizes and encodes path segments correctly', () {
      final req = CanonicalRequest(
        method: 'GET',
        url: Uri.parse('https://example.com').replace(
          pathSegments: ['mybucket', 'i+s.txt', 'foo+bar/baz'],
        ),
        queryParameters: {},
        headers: {'Host': 'example.com'},
        payloadHash: 'UNSIGNED-PAYLOAD',
      );

      expect(
        req.toString().split('\n')[1], // canonical URI index
        '/mybucket/i%2Bs.txt/foo%2Bbar%2Fbaz',
      );
    });
  });
}
