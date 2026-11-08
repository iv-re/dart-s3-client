import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:ctx/ctx.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:s3_client/s3_client.dart';
import 'package:s3_client/src/request.dart';
import 'package:s3_client/src/sign/signer.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(http.Request('GET', Uri()));
  });

  S3Client defaultClient(http.Client httpClient) {
    return S3Client(
      baseEndpoint: Uri.parse('https://s3.test'),
      credentials: S3CredentialsProvider.static(
        accessKeyId: 'test-key',
        secretAccessKey: 'test-secret',
      ),
      httpClient: httpClient,
    );
  }

  S3Signer defaultSigner() {
    return S3Signer(
      credentialsProvider: S3CredentialsProvider.static(
        accessKeyId: 'test-key',
        secretAccessKey: 'test-secret',
      ),
      region: 'us-east-1',
    );
  }

  http.StreamedResponse rawResponse(String body, {int status = 200}) {
    return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
  }

  http.StreamedResponse xmlResponse(
    XmlNode node, {
    int status = 200,
    Map<String, String>? headers,
  }) {
    return http.StreamedResponse(
      Stream.value(utf8.encode(node.toXmlString())),
      status,
      headers: headers ?? {},
    );
  }

  http.StreamedResponse emptyResponse({
    int status = 200,
    Map<String, String>? headers,
  }) {
    return http.StreamedResponse(
      const Stream.empty(),
      status,
      headers: headers ?? {},
    );
  }

  http.StreamedResponse embeddedErrorResponse() {
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          '<Error><Code>SlowDown</Code>'
          '<Message>Reduce your request rate.</Message></Error>',
        ),
      ),
      200,
    );
  }

  void s3ClientTest<T>(
    String description, {
    required FutureOr<T> Function(S3Client client) act,
    S3Client Function(http.Client httpClient)? build,
    http.StreamedResponse Function(http.BaseRequest request)? mockResponse,
    FutureOr<void> Function(http.BaseRequest request)? expectRequest,
    FutureOr<void> Function(List<http.BaseRequest> requests)? expectRequests,
    FutureOr<void> Function(List<int> body)? expectBody,
    FutureOr<void> Function(T result)? expectResponse,
  }) {
    assert(
      expectRequest == null || expectRequests == null,
      'Provide expectRequest or expectRequests, not both',
    );

    test(description, () async {
      final mockHttpClient = MockHttpClient();
      final s3client = (build ?? defaultClient)(mockHttpClient);

      final defaultResponse = http.StreamedResponse(
        Stream.value(Uint8List.fromList([1, 2, 3])),
        200,
        contentLength: 3,
        headers: {
          S3HttpHeaders.contentType: 'text/plain',
          S3HttpHeaders.etag: '"mock-etag"',
          S3HttpHeaders.contentLength: '3',
        },
      );

      final bodies = <Future<List<int>>>[];

      when(() => mockHttpClient.send(any())).thenAnswer(
        (invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          bodies.add(request.finalize().toBytes());
          return mockResponse?.call(request) ?? defaultResponse;
        },
      );

      final result = await act(s3client);

      final requests = verify(
        () => mockHttpClient.send(captureAny()),
      ).captured.cast<http.BaseRequest>().toList();

      if (expectRequest != null) {
        await expectRequest(requests.single);
      }
      if (expectRequests != null) {
        await expectRequests(requests);
      }
      if (expectBody != null) {
        await expectBody(await bodies.single);
      }
      if (expectResponse != null) {
        await expectResponse(result);
      }
    });
  }

  group('S3Client', () {
    s3ClientTest(
      'listObjectsV2 yields pages of objects',
      act: (client) => client
          .listObjectsV2(
            bucket: 'bucket',
            prefix: 'folder/',
            delimiter: '/',
            maxKeys: 50,
            startAfter: 'folder/z',
          )
          .toList(),
      mockResponse: (_) => xmlResponse(
        S3ListObjectsResult(
          name: 'bucket',
          prefix: 'folder/',
          maxKeys: 50,
          isTruncated: false,
          keyCount: 1,
          contents: [
            S3Object(
              key: 'folder/a',
              eTag: const S3Etag('etag-1'),
              size: 42,
              storageClass: 'STANDARD',
              lastModified: DateTime.utc(2026, 6, 25, 12, 30),
            ),
          ],
        ).toXml(),
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test?list-type=2'
          '&prefix=folder%2F&delimiter=%2F&max-keys=50&start-after=folder%2Fz',
        );
        expect(req.method, 'GET');
      },
      expectResponse: (result) {
        expect(result.length, 1);
        expect(result[0].name, 'bucket');
        final object = result[0].contents.single;
        expect(object.key, 'folder/a');
        expect(object.eTag, 'etag-1');
        expect(object.size, 42);
        expect(object.storageClass, 'STANDARD');
        expect(object.lastModified, DateTime.utc(2026, 6, 25, 12, 30));
      },
    );

    test('presignGetObject signs a GET request', () {
      return withClock(Clock.fixed(DateTime.utc(2026, 6, 25)), () async {
        final uri = await defaultClient(MockHttpClient()).presignGetObject(
          bucket: 'bucket',
          key: 'my-key',
          versionId: 'my-version-id',
          expires: const Duration(hours: 1),
        );

        expect(
          uri,
          await defaultSigner().presign(
            'GET',
            Uri.parse('https://bucket.s3.test/my-key?versionId=my-version-id'),
            expires: const Duration(hours: 1),
          ),
        );
        expect(uri.queryParameters['versionId'], 'my-version-id');
        expect(uri.queryParameters['X-Amz-Expires'], '3600');
      });
    });

    test('presignPutObject signs a PUT request', () {
      return withClock(Clock.fixed(DateTime.utc(2026, 6, 25)), () async {
        final uri = await defaultClient(MockHttpClient()).presignPutObject(
          bucket: 'bucket',
          key: 'my-key',
          expires: const Duration(hours: 1),
        );

        expect(
          uri,
          await defaultSigner().presign(
            'PUT',
            Uri.parse('https://bucket.s3.test/my-key'),
            expires: const Duration(hours: 1),
          ),
        );
        expect(uri.queryParameters['X-Amz-Expires'], '3600');
      });
    });

    s3ClientTest(
      'putObject uploads data and returns ETag',
      act: (client) => client.putObject(
        bucket: 'bucket',
        key: 'my-key',
        body: Stream.value(Uint8List.fromList([1, 2, 3])),
        contentType: 'application/octet-stream',
        contentDisposition: 'attachment; filename="file.bin"',
        contentEncoding: 'gzip',
        contentLanguage: 'en-US',
        cacheControl: 'max-age=3600',
        expires: DateTime.utc(2026, 6, 25, 12, 30),
        contentLength: 3,
        metadata: {'custom': 'value'},
        acl: S3ObjectAcl.publicRead,
        tagging: {'key1': 'val1', 'key2': 'val2'},
        storageClass: 'EXPRESS_ONEZONE',
        ifMatch: '"current-etag"',
        ifNoneMatch: '*',
      ),
      mockResponse: (_) => emptyResponse(
        headers: {
          S3HttpHeaders.etag: '"mock-etag"',
          S3HttpHeaders.versionId: 'version-123',
        },
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test/my-key',
        );
        expect(req.method, 'PUT');
        expect(
          req.headers[S3HttpHeaders.contentType],
          'application/octet-stream',
        );
        expect(
          req.headers[S3HttpHeaders.contentDisposition],
          'attachment; filename="file.bin"',
        );
        expect(req.headers[S3HttpHeaders.contentEncoding], 'gzip');
        expect(req.headers[S3HttpHeaders.contentLanguage], 'en-US');
        expect(req.headers[S3HttpHeaders.cacheControl], 'max-age=3600');
        expect(
          req.headers[S3HttpHeaders.expires],
          'Thu, 25 Jun 2026 12:30:00 GMT',
        );
        expect(req.headers['x-amz-meta-custom'], 'value');
        expect(req.headers[S3HttpHeaders.acl], 'public-read');
        expect(req.headers[S3HttpHeaders.tagging], 'key1=val1&key2=val2');
        expect(req.headers[S3HttpHeaders.storageClass], 'EXPRESS_ONEZONE');
        expect(req.headers[S3HttpHeaders.ifMatch], '"current-etag"');
        expect(req.headers[S3HttpHeaders.ifNoneMatch], '*');
      },
      expectBody: (body) => expect(body, [1, 2, 3]),
      expectResponse: (result) {
        expect(result.eTag, 'mock-etag');
        expect(result.versionId, 'version-123');
      },
    );

    test('putObject throws when the connection fails', () async {
      final mockHttpClient = MockHttpClient();
      when(() => mockHttpClient.send(any())).thenAnswer(
        (_) async => throw http.ClientException('Connection refused'),
      );

      final upload = defaultClient(mockHttpClient).putObject(
        bucket: 'bucket',
        key: 'my-key',
        body: Stream.value(Uint8List.fromList([1, 2, 3])),
        contentLength: 3,
      );

      await expectLater(
        upload.timeout(const Duration(seconds: 1)),
        throwsA(isA<http.ClientException>()),
      );
    });

    s3ClientTest(
      'getObject with no optional arguments has standard headers and '
      'no versionId',
      act: (client) => client.getObject(bucket: 'bucket', key: 'my-key'),
      expectRequest: (req) {
        expect(req.url.toString(), 'https://bucket.s3.test/my-key');
        expect(req.headers.containsKey(S3HttpHeaders.range), isFalse);
        expect(req.headers.containsKey(S3HttpHeaders.ifMatch), isFalse);
        expect(req.headers.containsKey(S3HttpHeaders.ifNoneMatch), isFalse);
        expect(req.headers.containsKey(S3HttpHeaders.ifModifiedSince), isFalse);
        expect(
          req.headers.containsKey(S3HttpHeaders.ifUnmodifiedSince),
          isFalse,
        );
      },
      expectResponse: (result) async {
        expect(result.contentType, 'text/plain');
        expect(result.contentLength, 3);
        expect(await result.toBytes(), Uint8List.fromList([1, 2, 3]));
      },
    );

    s3ClientTest(
      'getObject parses all response headers and metadata',
      act: (client) => client.getObject(
        bucket: 'bucket',
        key: 'my-key',
        range: 'bytes=0-1023',
        versionId: 'v123',
        ifMatch: 'etag123',
        ifNoneMatch: 'etag456',
        ifModifiedSince: DateTime.utc(2026, 6, 25, 12, 30),
        ifUnmodifiedSince: DateTime.utc(2026, 6, 25, 14, 45),
      ),
      mockResponse: (_) => http.StreamedResponse(
        const Stream.empty(),
        200,
        contentLength: 3,
        headers: {
          S3HttpHeaders.contentType: 'text/plain',
          S3HttpHeaders.contentLength: '3',
          S3HttpHeaders.etag: '"mock-etag"',
          S3HttpHeaders.lastModified: 'Thu, 25 Jun 2026 12:30:00 GMT',
          S3HttpHeaders.versionId: 'version-123',
          S3HttpHeaders.deleteMarker: 'true',
          'x-amz-meta-custom': 'val',
          S3HttpHeaders.storageClass: 'STANDARD',
          S3HttpHeaders.acceptRanges: 'bytes',
        },
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test/my-key?versionId=v123',
        );
        expect(req.headers[S3HttpHeaders.range], 'bytes=0-1023');
        expect(req.headers[S3HttpHeaders.ifMatch], 'etag123');
        expect(req.headers[S3HttpHeaders.ifNoneMatch], 'etag456');
        expect(
          req.headers[S3HttpHeaders.ifModifiedSince],
          'Thu, 25 Jun 2026 12:30:00 GMT',
        );
        expect(
          req.headers[S3HttpHeaders.ifUnmodifiedSince],
          'Thu, 25 Jun 2026 14:45:00 GMT',
        );
      },
      expectResponse: (result) async {
        expect(result.contentType, 'text/plain');
        expect(result.contentLength, 3);
        expect(result.eTag, 'mock-etag');
        expect(result.lastModified, DateTime.utc(2026, 6, 25, 12, 30));
        expect(result.versionId, 'version-123');
        expect(result.deleteMarker, isTrue);
        expect(result.metadata['custom'], 'val');
        expect(result.storageClass, 'STANDARD');
        expect(result.acceptRanges, 'bytes');
      },
    );

    s3ClientTest(
      'deleteObject deletes object',
      act: (client) => client.deleteObject(
        bucket: 'bucket',
        key: 'my-key',
        versionId: 'v1',
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test/my-key?versionId=v1',
        );
        expect(req.method, 'DELETE');
      },
    );

    s3ClientTest(
      'headObject returns object metadata',
      act: (client) => client.headObject(
        bucket: 'bucket',
        key: 'my-key',
        versionId: 'v123',
        partNumber: 2,
        ifMatch: 'etag123',
        ifNoneMatch: 'etag456',
        ifModifiedSince: DateTime.utc(2026, 6, 25, 12, 30),
        ifUnmodifiedSince: DateTime.utc(2026, 6, 25, 14, 45),
      ),
      mockResponse: (_) => emptyResponse(
        headers: {
          S3HttpHeaders.contentType: 'text/plain',
          S3HttpHeaders.etag: '"mock-etag"',
          S3HttpHeaders.contentLength: '3',
          S3HttpHeaders.lastModified: 'Thu, 25 Jun 2026 12:30:00 GMT',
          S3HttpHeaders.versionId: 'v123',
          S3HttpHeaders.cacheControl: 'public, max-age=3600',
          S3HttpHeaders.contentDisposition: 'attachment; filename="file.txt"',
          S3HttpHeaders.contentEncoding: 'gzip',
          S3HttpHeaders.contentLanguage: 'en-US',
          S3HttpHeaders.expires: 'Thu, 26 Jun 2026 12:30:00 GMT',
          S3HttpHeaders.acceptRanges: 'bytes',
        },
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test/my-key?versionId=v123&partNumber=2',
        );
        expect(req.method, 'HEAD');
        expect(req.headers[S3HttpHeaders.ifMatch], 'etag123');
        expect(req.headers[S3HttpHeaders.ifNoneMatch], 'etag456');
        expect(
          req.headers[S3HttpHeaders.ifModifiedSince],
          'Thu, 25 Jun 2026 12:30:00 GMT',
        );
        expect(
          req.headers[S3HttpHeaders.ifUnmodifiedSince],
          'Thu, 25 Jun 2026 14:45:00 GMT',
        );
      },
      expectResponse: (result) {
        expect(result.contentType, 'text/plain');
        expect(result.contentLength, 3);
        expect(result.eTag, 'mock-etag');
        expect(result.lastModified, DateTime.utc(2026, 6, 25, 12, 30));
        expect(result.versionId, 'v123');
        expect(result.cacheControl, 'public, max-age=3600');
        expect(result.contentDisposition, 'attachment; filename="file.txt"');
        expect(result.contentEncoding, 'gzip');
        expect(result.contentLanguage, 'en-US');
        expect(result.expires, DateTime.utc(2026, 6, 26, 12, 30));
        expect(result.acceptRanges, 'bytes');
      },
    );

    test('headObject throws S3NoSuchKeyException on 404', () async {
      final mockHttpClient = MockHttpClient();
      final s3client = defaultClient(mockHttpClient);

      when(() => mockHttpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(Uint8List(0)),
          404,
          reasonPhrase: 'Not Found',
        ),
      );

      expect(
        () => s3client.headObject(bucket: 'bucket', key: 'my-key'),
        throwsA(isA<S3NoSuchKeyException>()),
      );
    });

    test('headObject throws S3UnknownException on non-404 error', () async {
      final mockHttpClient = MockHttpClient();
      final s3client = defaultClient(mockHttpClient);

      when(() => mockHttpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(
            utf8.encode(
              '<Error><Code>Forbidden</Code>'
              '<Message>Access Denied</Message></Error>',
            ),
          ),
          403,
          reasonPhrase: 'Forbidden',
          headers: {S3HttpHeaders.contentType: 'application/xml'},
        ),
      );

      expect(
        () => s3client.headObject(bucket: 'bucket', key: 'my-key'),
        throwsA(isA<S3UnknownException>()),
      );
    });

    final emptyBodyErrors = <(int, Matcher)>[
      (304, isA<S3NotModifiedException>()),
      (403, isA<S3AccessDeniedException>()),
      (412, isA<S3PreconditionFailedException>()),
    ];
    for (final (status, matcher) in emptyBodyErrors) {
      s3ClientTest(
        'headObject maps status $status without a body',
        mockResponse: (_) => emptyResponse(status: status),
        act: (client) => expectLater(
          client.headObject(bucket: 'bucket', key: 'my-key'),
          throwsA(matcher),
        ),
      );
    }

    s3ClientTest(
      'copyObject copies object',
      act: (client) => client.copyObject(
        bucket: 'bucket',
        key: 'my-key',
        copySource: 'src-bucket/src-key with spaces/i+s.txt/literal%2Bpercent',
        contentType: 'text/plain',
        contentDisposition: 'attachment; filename="file.txt"',
        contentEncoding: 'gzip',
        contentLanguage: 'en-US',
        cacheControl: 'max-age=3600',
        expires: DateTime.utc(2026, 6, 25, 12, 30),
        metadataDirective: S3MetadataDirective.replace,
        metadata: {'custom': 'new-val'},
        acl: S3ObjectAcl.publicRead,
        tagging: {'copied': 'true'},
        storageClass: 'INTELLIGENT_TIERING',
      ),
      mockResponse: (_) => xmlResponse(
        S3CopyObjectResult(
          eTag: const S3Etag('mock-etag'),
          lastModified: DateTime.utc(2026, 6, 25, 12, 30),
        ).toXml(),
        headers: {
          S3HttpHeaders.versionId: 'dest-version-1',
          S3HttpHeaders.copySourceVersionId: 'src-version-1',
        },
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test/my-key',
        );
        expect(req.method, 'PUT');
        expect(
          req.headers[S3HttpHeaders.copySource],
          'src-bucket/src-key%20with%20spaces/i%2Bs.txt/literal%252Bpercent',
        );
        expect(req.headers[S3HttpHeaders.contentType], 'text/plain');
        expect(
          req.headers[S3HttpHeaders.contentDisposition],
          'attachment; filename="file.txt"',
        );
        expect(req.headers[S3HttpHeaders.contentEncoding], 'gzip');
        expect(req.headers[S3HttpHeaders.contentLanguage], 'en-US');
        expect(req.headers[S3HttpHeaders.cacheControl], 'max-age=3600');
        expect(
          req.headers[S3HttpHeaders.expires],
          'Thu, 25 Jun 2026 12:30:00 GMT',
        );
        expect(req.headers[S3HttpHeaders.metadataDirective], 'REPLACE');
        expect(req.headers['x-amz-meta-custom'], 'new-val');
        expect(req.headers[S3HttpHeaders.acl], 'public-read');
        expect(req.headers[S3HttpHeaders.tagging], 'copied=true');
        expect(req.headers[S3HttpHeaders.taggingDirective], 'REPLACE');
        expect(req.headers[S3HttpHeaders.storageClass], 'INTELLIGENT_TIERING');
      },
      expectResponse: (result) {
        expect(result.eTag, 'mock-etag');
        expect(result.lastModified, DateTime.utc(2026, 6, 25, 12, 30));
        expect(result.versionId, 'dest-version-1');
        expect(result.copySourceVersionId, 'src-version-1');
      },
    );

    s3ClientTest(
      'copyObject passes copy source conditional arguments correctly',
      act: (client) => client.copyObject(
        bucket: 'bucket',
        key: 'my-key',
        copySource: 'src-bucket/src-key',
        contentType: 'application/octet-stream',
        copySourceIfMatch: '"source-etag"',
        copySourceIfNoneMatch: '"not-this-etag"',
        copySourceIfModifiedSince: DateTime.utc(2026, 6, 25, 12, 30),
        copySourceIfUnmodifiedSince: DateTime.utc(2026, 6, 25, 14, 45),
      ),
      mockResponse: (_) => xmlResponse(
        S3CopyObjectResult(
          eTag: const S3Etag('mock-etag'),
          lastModified: DateTime.utc(2026, 6, 25, 12, 30),
        ).toXml(),
        headers: {
          S3HttpHeaders.versionId: 'dest-version-2',
          S3HttpHeaders.copySourceVersionId: 'src-version-2',
        },
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test/my-key',
        );
        expect(req.method, 'PUT');
        expect(req.headers[S3HttpHeaders.copySource], 'src-bucket/src-key');
        expect(
          req.headers[S3HttpHeaders.contentType],
          'application/octet-stream',
        );
        expect(
          req.headers[S3HttpHeaders.copySourceIfMatch],
          '"source-etag"',
        );
        expect(
          req.headers[S3HttpHeaders.copySourceIfNoneMatch],
          '"not-this-etag"',
        );
        expect(
          req.headers[S3HttpHeaders.copySourceIfModifiedSince],
          'Thu, 25 Jun 2026 12:30:00 GMT',
        );
        expect(
          req.headers[S3HttpHeaders.copySourceIfUnmodifiedSince],
          'Thu, 25 Jun 2026 14:45:00 GMT',
        );
      },
      expectResponse: (result) {
        expect(result.eTag, 'mock-etag');
        expect(result.lastModified, DateTime.utc(2026, 6, 25, 12, 30));
        expect(result.versionId, 'dest-version-2');
        expect(result.copySourceVersionId, 'src-version-2');
      },
    );

    s3ClientTest(
      'copyObject copies a specific source version and keeps source tags',
      act: (client) => client.copyObject(
        bucket: 'bucket',
        key: 'my-key',
        copySource: 'src-bucket/src key',
        copySourceVersionId: 'v+1/a',
      ),
      mockResponse: (_) => xmlResponse(
        S3CopyObjectResult(
          eTag: const S3Etag('mock-etag'),
          lastModified: DateTime.utc(2026, 6, 25, 12, 30),
        ).toXml(),
      ),
      expectRequest: (req) {
        expect(
          req.headers[S3HttpHeaders.copySource],
          'src-bucket/src%20key?versionId=v%2B1%2Fa',
        );
        expect(req.headers, isNot(contains(S3HttpHeaders.taggingDirective)));
      },
    );

    s3ClientTest(
      'copyObject throws error embedded in 200 response',
      mockResponse: (_) => embeddedErrorResponse(),
      act: (client) => expectLater(
        client.copyObject(
          bucket: 'bucket',
          key: 'my-key',
          copySource: 'src-bucket/src-key',
        ),
        throwsA(isA<S3SlowDownException>()),
      ),
    );

    s3ClientTest(
      'createMultipartUpload initiates upload',
      act: (client) => client.createMultipartUpload(
        bucket: 'bucket',
        key: 'my-key',
        contentType: 'text/plain',
        contentDisposition: 'attachment; filename="file.txt"',
        contentEncoding: 'gzip',
        contentLanguage: 'en-US',
        cacheControl: 'max-age=3600',
        expires: DateTime.utc(2026, 6, 25, 12, 30),
        metadata: {'custom': 'value'},
        acl: S3ObjectAcl.private,
        tagging: {'project': 'pusk'},
        storageClass: 'GLACIER_IR',
      ),
      mockResponse: (_) => xmlResponse(const S3UploadId('upload-123').toXml()),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test/my-key?uploads',
        );
        expect(req.method, 'POST');
        expect(req.headers[S3HttpHeaders.contentType], 'text/plain');
        expect(
          req.headers[S3HttpHeaders.contentDisposition],
          'attachment; filename="file.txt"',
        );
        expect(req.headers[S3HttpHeaders.contentEncoding], 'gzip');
        expect(req.headers[S3HttpHeaders.contentLanguage], 'en-US');
        expect(req.headers[S3HttpHeaders.cacheControl], 'max-age=3600');
        expect(
          req.headers[S3HttpHeaders.expires],
          'Thu, 25 Jun 2026 12:30:00 GMT',
        );
        expect(req.headers['x-amz-meta-custom'], 'value');
        expect(req.headers[S3HttpHeaders.acl], 'private');
        expect(req.headers[S3HttpHeaders.tagging], 'project=pusk');
        expect(req.headers[S3HttpHeaders.storageClass], 'GLACIER_IR');
      },
      expectResponse: (uploadId) {
        expect(uploadId, 'upload-123');
      },
    );

    s3ClientTest(
      'uploadPart uploads part',
      act: (client) => client.uploadPart(
        bucket: 'bucket',
        key: 'my-key',
        uploadId: 'upload-123',
        partNumber: 2,
        body: Stream.value(Uint8List.fromList([1, 2, 3])),
        contentLength: 3,
      ),
      mockResponse: (_) => emptyResponse(
        headers: {
          S3HttpHeaders.etag: '"mock-etag"',
        },
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test/my-key?uploadId=upload-123&partNumber=2',
        );
        expect(req.method, 'PUT');
      },
      expectBody: (body) => expect(body, [1, 2, 3]),
      expectResponse: (etag) {
        expect(etag, 'mock-etag');
      },
    );

    s3ClientTest(
      'completeMultipartUpload completes upload',
      act: (client) => client.completeMultipartUpload(
        bucket: 'bucket',
        key: 'my-key',
        uploadId: 'upload-123',
        multipartUpload: const S3CompleteMultipartUpload(
          parts: [
            S3CompletedPart(partNumber: 2, eTag: S3Etag('etag-2')),
            S3CompletedPart(partNumber: 1, eTag: S3Etag('etag-1')),
          ],
        ),
        ifMatch: '"current-etag"',
        ifNoneMatch: '*',
      ),
      mockResponse: (_) => xmlResponse(
        const S3CompleteMultipartUploadResult(
          location: 'https://bucket.s3.test/my-key',
          bucket: 'bucket',
          key: 'my-key',
          eTag: S3Etag('mock-etag'),
        ).toXml(),
        headers: {S3HttpHeaders.versionId: 'v999'},
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test/my-key?uploadId=upload-123',
        );
        expect(req.method, 'POST');
        expect(req.headers[S3HttpHeaders.ifMatch], '"current-etag"');
        expect(req.headers[S3HttpHeaders.ifNoneMatch], '*');

        final body = XmlDocument.parse((req as http.Request).body).rootElement;
        expect(body.name.local, 'CompleteMultipartUpload');
        expect(
          body.getAttribute('xmlns'),
          'http://s3.amazonaws.com/doc/2006-03-01/',
        );
        expect(
          body.findAllElements('PartNumber').map((e) => e.innerText),
          ['1', '2'],
        );
        expect(
          body.findAllElements('ETag').map((e) => e.innerText),
          ['"etag-1"', '"etag-2"'],
        );
      },
      expectResponse: (result) {
        expect(result.location, 'https://bucket.s3.test/my-key');
        expect(result.bucket, 'bucket');
        expect(result.key, 'my-key');
        expect(result.eTag, 'mock-etag');
        expect(result.versionId, 'v999');
      },
    );

    s3ClientTest(
      'completeMultipartUpload throws error embedded in 200 response',
      mockResponse: (_) => embeddedErrorResponse(),
      act: (client) => expectLater(
        client.completeMultipartUpload(
          bucket: 'bucket',
          key: 'my-key',
          uploadId: 'upload-123',
          multipartUpload: const S3CompleteMultipartUpload(parts: []),
        ),
        throwsA(isA<S3SlowDownException>()),
      ),
    );

    s3ClientTest(
      'abortMultipartUpload aborts upload',
      act: (client) => client.abortMultipartUpload(
        bucket: 'bucket',
        key: 'my-key',
        uploadId: 'upload-123',
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test/my-key?uploadId=upload-123',
        );
        expect(req.method, 'DELETE');
      },
    );

    s3ClientTest(
      'deleteObjects deletes multiple objects',
      act: (client) => client.deleteObjects(
        bucket: 'bucket',
        objects: const [
          S3ObjectIdentifier(key: 'key1'),
          S3ObjectIdentifier(key: 'key2', versionId: 'v2'),
        ],
        quiet: true,
      ),
      mockResponse: (_) => xmlResponse(
        const S3DeleteObjectsResult(
          deleted: [
            S3DeletedObject(key: 'key1'),
            S3DeletedObject(
              key: 'key2',
              versionId: 'v2',
            ),
          ],
        ).toXml(),
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test?delete',
        );
        expect(req.method, 'POST');
        final request = req as http.Request;
        expect(
          req.headers[S3HttpHeaders.contentMd5],
          base64Encode(md5.convert(request.bodyBytes).bytes),
        );
        expect(
          request.body,
          '<Delete><Quiet>true</Quiet>'
          '<Object><Key>key1</Key></Object>'
          '<Object><Key>key2</Key><VersionId>v2</VersionId></Object>'
          '</Delete>',
        );
      },
      expectResponse: (result) {
        expect(result.deleted.length, 2);
        expect(result.deleted[0].key, 'key1');
        expect(result.deleted[1].key, 'key2');
        expect(result.deleted[1].versionId, 'v2');
        expect(result.errors, isEmpty);
      },
    );

    s3ClientTest(
      'deleteObjects chunks requests when >1000 objects',
      act: (client) async {
        final objects = List.generate(
          1001,
          (i) => S3ObjectIdentifier(key: 'key$i'),
        );
        return client.deleteObjects(
          bucket: 'bucket',
          objects: objects,
        );
      },
      mockResponse: (_) => xmlResponse(
        const S3DeleteObjectsResult(
          deleted: [S3DeletedObject(key: 'key')],
        ).toXml(),
      ),
      expectRequests: (requests) {
        expect(
          requests.map(
            (req) => XmlDocument.parse(
              (req as http.Request).body,
            ).rootElement.findElements('Object').length,
          ),
          [1000, 1],
        );
        for (final req in requests) {
          expect(
            req.url.toString(),
            'https://bucket.s3.test?delete',
          );
          expect(req.method, 'POST');
        }
      },
      expectResponse: (result) {
        expect(result.deleted.length, 2);
        expect(result.errors, isEmpty);
      },
    );

    s3ClientTest(
      'deleteObjects sends exactly 1000 objects in one request',
      act: (client) => client.deleteObjects(
        bucket: 'bucket',
        objects: List.generate(
          1000,
          (i) => S3ObjectIdentifier(key: 'key$i'),
        ),
      ),
      mockResponse: (_) => xmlResponse(const S3DeleteObjectsResult().toXml()),
      expectRequest: (req) {
        expect((req as http.Request).body, isNot(contains('<Quiet>')));
      },
    );

    s3ClientTest(
      'listParts yields pages of parts',
      act: (client) => client
          .listParts(
            bucket: 'bucket',
            key: 'my-key',
            uploadId: 'upload-123',
            maxParts: 50,
          )
          .toList(),
      mockResponse: (_) => xmlResponse(
        S3ListPartsResult(
          bucket: 'bucket',
          key: 'my-key',
          uploadId: 'upload-123',
          partNumberMarker: 0,
          maxParts: 50,
          isTruncated: false,
          parts: [
            S3Part(
              partNumber: 1,
              lastModified: DateTime.utc(2026, 6, 25, 12, 30),
              eTag: const S3Etag('etag-1'),
              size: 100,
            ),
          ],
        ).toXml(),
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test/my-key?uploadId=upload-123&max-parts=50',
        );
        expect(req.method, 'GET');
      },
      expectResponse: (pages) {
        expect(pages.length, 1);
        expect(pages[0].parts.length, 1);
        expect(pages[0].parts[0].partNumber, 1);
        expect(pages[0].parts[0].eTag, 'etag-1');
        expect(pages[0].parts[0].size, 100);
      },
    );

    s3ClientTest(
      'uploadPartCopy copies part',
      act: (client) => client.uploadPartCopy(
        bucket: 'bucket',
        key: 'my-key',
        uploadId: 'upload-123',
        partNumber: 2,
        copySource: 'src-bucket/src-key with spaces/i+s.txt/literal%2Bpercent',
        copySourceRange: 'bytes=0-1048575',
        copySourceIfMatch: '"src-etag"',
        copySourceIfNoneMatch: '"not-this"',
        copySourceIfModifiedSince: DateTime.utc(2026, 6, 25, 12, 30),
        copySourceIfUnmodifiedSince: DateTime.utc(2026, 6, 25, 14, 45),
      ),
      mockResponse: (_) => xmlResponse(
        S3CopyPartResult(
          eTag: const S3Etag('copied-etag'),
          lastModified: DateTime.utc(2026, 6, 25, 12, 30),
        ).toXml(),
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test/my-key?partNumber=2&uploadId=upload-123',
        );
        expect(req.method, 'PUT');
        expect(
          req.headers[S3HttpHeaders.copySource],
          'src-bucket/src-key%20with%20spaces/i%2Bs.txt/literal%252Bpercent',
        );
        expect(
          req.headers[S3HttpHeaders.copySourceRange],
          'bytes=0-1048575',
        );
        expect(
          req.headers[S3HttpHeaders.copySourceIfMatch],
          '"src-etag"',
        );
        expect(
          req.headers[S3HttpHeaders.copySourceIfNoneMatch],
          '"not-this"',
        );
        expect(
          req.headers[S3HttpHeaders.copySourceIfModifiedSince],
          'Thu, 25 Jun 2026 12:30:00 GMT',
        );
        expect(
          req.headers[S3HttpHeaders.copySourceIfUnmodifiedSince],
          'Thu, 25 Jun 2026 14:45:00 GMT',
        );
      },
      expectResponse: (result) {
        expect(result.eTag, 'copied-etag');
        expect(
          result.lastModified,
          DateTime.utc(2026, 6, 25, 12, 30),
        );
      },
    );

    s3ClientTest(
      'uploadPartCopy copies a specific source version',
      act: (client) => client.uploadPartCopy(
        bucket: 'bucket',
        key: 'my-key',
        uploadId: 'upload-123',
        partNumber: 1,
        copySource: 'src-bucket/src-key',
        copySourceVersionId: 'v1',
      ),
      mockResponse: (_) => xmlResponse(
        S3CopyPartResult(
          eTag: const S3Etag('copied-etag'),
          lastModified: DateTime.utc(2026, 6, 25, 12, 30),
        ).toXml(),
      ),
      expectRequest: (req) {
        expect(
          req.headers[S3HttpHeaders.copySource],
          'src-bucket/src-key?versionId=v1',
        );
      },
    );

    s3ClientTest(
      'uploadPartCopy throws error embedded in 200 response',
      mockResponse: (_) => embeddedErrorResponse(),
      act: (client) => expectLater(
        client.uploadPartCopy(
          bucket: 'bucket',
          key: 'my-key',
          uploadId: 'upload-123',
          partNumber: 1,
          copySource: 'src-bucket/src-key',
        ),
        throwsA(isA<S3SlowDownException>()),
      ),
    );

    s3ClientTest(
      'listMultipartUploads yields pages of uploads',
      act: (client) {
        return client
            .listMultipartUploads(
              bucket: 'bucket',
              prefix: 'folder/',
              delimiter: '/',
              maxUploads: 50,
            )
            .toList();
      },
      mockResponse: (_) => xmlResponse(
        const S3ListMultipartUploadsResult(
          bucket: 'bucket',
          maxUploads: 50,
          isTruncated: false,
          uploads: [
            S3MultipartUpload(
              key: 'my-key',
              uploadId: 'upload-123',
            ),
          ],
        ).toXml(),
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test?uploads'
          '&prefix=folder%2F&delimiter=%2F&max-uploads=50',
        );
        expect(req.method, 'GET');
      },
      expectResponse: (pages) {
        expect(pages.length, 1);
        expect(pages[0].uploads.length, 1);
        expect(pages[0].uploads[0].key, 'my-key');
        expect(pages[0].uploads[0].uploadId, 'upload-123');
      },
    );

    s3ClientTest(
      'listObjectVersions yields pages of versions',
      act: (client) {
        return client
            .listObjectVersions(
              bucket: 'bucket',
              maxKeys: 2,
              prefix: 'folder/',
              delimiter: '/',
            )
            .toList();
      },
      mockResponse: (_) => xmlResponse(
        S3ListObjectVersionsResult(
          name: 'bucket',
          maxKeys: 2,
          isTruncated: false,
          versions: [
            S3ObjectVersion(
              key: 'file.txt',
              versionId: 'abc123',
              isLatest: true,
              lastModified: DateTime.utc(2026, 6, 25, 12),
              eTag: const S3Etag('etag1'),
              size: 100,
              storageClass: 'STANDARD',
            ),
          ],
          deleteMarkers: [
            S3DeleteMarkerEntry(
              key: 'old.txt',
              versionId: 'del456',
              isLatest: true,
              lastModified: DateTime.utc(2026, 6, 24, 12),
            ),
          ],
        ).toXml(),
      ),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test?versions'
          '&prefix=folder%2F&delimiter=%2F&max-keys=2',
        );
        expect(req.method, 'GET');
      },
      expectResponse: (pages) {
        expect(pages.length, 1);
        expect(pages[0].versions.length, 1);
        expect(pages[0].versions[0].key, 'file.txt');
        expect(pages[0].versions[0].versionId, 'abc123');
        expect(pages[0].versions[0].isLatest, isTrue);
        expect(pages[0].deleteMarkers.length, 1);
        expect(pages[0].deleteMarkers[0].key, 'old.txt');
        expect(pages[0].deleteMarkers[0].versionId, 'del456');
      },
    );

    s3ClientTest(
      'uses path-style URL when usePathStyle is true',
      build: (httpClient) => S3Client(
        baseEndpoint: Uri.parse('https://s3.test'),
        credentials: S3CredentialsProvider.static(
          accessKeyId: 'test-key',
          secretAccessKey: 'test-secret',
        ),
        httpClient: httpClient,
        usePathStyle: true,
      ),
      act: (client) => client.getObject(bucket: 'bucket', key: 'folder/my-key'),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://s3.test/bucket/folder/my-key',
        );
      },
    );

    s3ClientTest(
      'S3Client.aws() uses the correct endpoint',
      build: (httpClient) => S3Client.aws(
        region: 'eu-west-1',
        credentials: S3CredentialsProvider.static(
          accessKeyId: 'test-key',
          secretAccessKey: 'test-secret',
        ),
        httpClient: httpClient,
      ),
      act: (client) => client.getObject(bucket: 'bucket', key: 'my-key'),
      expectRequest: (req) {
        expect(req.url.host, 'bucket.s3.eu-west-1.amazonaws.com');
        expect(
          req.headers[S3HttpHeaders.authorization],
          contains('/eu-west-1/s3/aws4_request'),
        );
      },
    );

    s3ClientTest(
      'S3Client.r2() uses the correct endpoint',
      build: (httpClient) => S3Client.r2(
        accountId: 'my-account',
        credentials: S3CredentialsProvider.static(
          accessKeyId: 'test-key',
          secretAccessKey: 'test-secret',
        ),
        httpClient: httpClient,
      ),
      act: (client) => client.getObject(bucket: 'bucket', key: 'my-key'),
      expectRequest: (req) {
        expect(
          req.url.host,
          'bucket.my-account.r2.cloudflarestorage.com',
        );
        expect(
          req.headers[S3HttpHeaders.authorization],
          contains('/auto/s3/aws4_request'),
        );
      },
    );

    s3ClientTest(
      'listObjectsV2 paginates with continuation token',
      act: (client) {
        return client.listObjectsV2(bucket: 'bucket', maxKeys: 1).toList();
      },
      mockResponse: (req) {
        if (req.url.queryParameters.containsKey('continuation-token')) {
          return xmlResponse(
            const S3ListObjectsResult(
              name: 'bucket',
              prefix: '',
              maxKeys: 1,
              isTruncated: false,
              keyCount: 0,
              contents: [],
            ).toXml(),
          );
        }
        return xmlResponse(
          const S3ListObjectsResult(
            name: 'bucket',
            prefix: '',
            maxKeys: 1,
            isTruncated: true,
            keyCount: 0,
            contents: [],
            nextContinuationToken: 'token1',
          ).toXml(),
        );
      },
      expectRequests: (requests) {
        expect(
          requests.first.url.queryParameters,
          isNot(contains('continuation-token')),
        );
        expect(
          requests.last.url.queryParameters['continuation-token'],
          'token1',
        );
      },
      expectResponse: (pages) {
        expect(pages.length, 2);
      },
    );

    s3ClientTest(
      'listParts paginates with part number marker',
      act: (client) => client
          .listParts(
            bucket: 'bucket',
            key: 'my-key',
            uploadId: 'upload-123',
          )
          .toList(),
      mockResponse: (req) {
        if (req.url.queryParameters.containsKey('part-number-marker')) {
          return xmlResponse(
            const S3ListPartsResult(
              bucket: 'bucket',
              key: 'my-key',
              uploadId: 'upload-123',
              partNumberMarker: 1,
              maxParts: 1000,
              isTruncated: false,
            ).toXml(),
          );
        }

        return xmlResponse(
          const S3ListPartsResult(
            bucket: 'bucket',
            key: 'my-key',
            uploadId: 'upload-123',
            partNumberMarker: 0,
            nextPartNumberMarker: 1,
            maxParts: 1000,
            isTruncated: true,
          ).toXml(),
        );
      },
      expectRequests: (requests) {
        expect(
          requests.first.url.queryParameters,
          isNot(contains('part-number-marker')),
        );
        expect(
          requests.last.url.queryParameters['part-number-marker'],
          '1',
        );
      },
      expectResponse: (pages) {
        expect(pages.length, 2);
      },
    );

    s3ClientTest(
      'listMultipartUploads paginates with key and upload markers',
      act: (client) => client.listMultipartUploads(bucket: 'bucket').toList(),
      mockResponse: (req) {
        if (req.url.queryParameters.containsKey('key-marker')) {
          return xmlResponse(
            const S3ListMultipartUploadsResult(
              bucket: 'bucket',
              maxUploads: 1000,
              isTruncated: false,
            ).toXml(),
          );
        }

        return xmlResponse(
          const S3ListMultipartUploadsResult(
            bucket: 'bucket',
            maxUploads: 1000,
            isTruncated: true,
            nextKeyMarker: 'next-key',
            nextUploadIdMarker: 'next-id',
          ).toXml(),
        );
      },
      expectRequests: (requests) {
        final query = requests.last.url.queryParameters;
        expect(
          requests.first.url.queryParameters,
          isNot(contains('key-marker')),
        );
        expect(query['key-marker'], 'next-key');
        expect(query['upload-id-marker'], 'next-id');
      },
      expectResponse: (pages) {
        expect(pages.length, 2);
      },
    );

    s3ClientTest(
      'listObjectVersions paginates with key and version markers',
      act: (client) => client.listObjectVersions(bucket: 'bucket').toList(),
      mockResponse: (req) {
        if (req.url.queryParameters.containsKey('key-marker')) {
          return xmlResponse(
            const S3ListObjectVersionsResult(
              name: 'bucket',
              maxKeys: 1000,
              isTruncated: false,
            ).toXml(),
          );
        }

        return xmlResponse(
          const S3ListObjectVersionsResult(
            name: 'bucket',
            maxKeys: 1000,
            isTruncated: true,
            nextKeyMarker: 'next-key',
            nextVersionIdMarker: 'next-version',
          ).toXml(),
        );
      },
      expectRequests: (requests) {
        final query = requests.last.url.queryParameters;
        expect(
          requests.first.url.queryParameters,
          isNot(contains('key-marker')),
        );
        expect(query['key-marker'], 'next-key');
        expect(query['version-id-marker'], 'next-version');
      },
      expectResponse: (pages) {
        expect(pages.length, 2);
      },
    );

    s3ClientTest(
      'encodes plus sign in key',
      act: (client) => client.deleteObject(bucket: 'bucket', key: 'a+b c'),
      expectRequest: (req) {
        expect(req.url.toString(), 'https://bucket.s3.test/a%2Bb%20c');
        expect(req.url.pathSegments, ['a+b c']);
      },
    );

    for (final key in ['a/../b', 'a/./b', '../x', '.']) {
      test('rejects dot segments in key "$key"', () async {
        final client = defaultClient(MockHttpClient());

        await expectLater(
          client.deleteObject(bucket: 'bucket', key: key),
          throwsArgumentError,
        );
        await expectLater(
          client.presignGetObject(bucket: 'bucket', key: key),
          throwsArgumentError,
        );
      });
    }

    group('tolerates', () {
      test('listing entries without StorageClass', () {
        final list = S3ListObjectsResult.fromXmlDocument(
          '<ListBucketResult><Name>b</Name><MaxKeys>1</MaxKeys>'
          '<IsTruncated>false</IsTruncated><Contents><Key>k</Key>'
          '<ETag>"e"</ETag><Size>1</Size>'
          '<LastModified>2026-06-25T12:30:00.000Z</LastModified>'
          '</Contents></ListBucketResult>',
        );

        expect(list.contents.single.storageClass, 'STANDARD');
      });

      test('part listings without PartNumberMarker', () {
        final parts = S3ListPartsResult.fromXmlDocument(
          '<ListPartsResult><Bucket>b</Bucket><Key>k</Key>'
          '<UploadId>u</UploadId><MaxParts>1</MaxParts>'
          '<IsTruncated>false</IsTruncated></ListPartsResult>',
        );

        expect(parts.partNumberMarker, 0);
      });

      test('errors without Message', () {
        final error = S3Error.fromXmlDocument(
          '<Error><Code>SlowDown</Code></Error>',
        );

        expect(error.code, 'SlowDown');
        expect(error.message, '');
      });

      test('invalid Expires header', () {
        final head = S3HeadObjectResult.fromHeaders({
          S3HttpHeaders.expires: '0',
        });

        expect(head.expires, isNull);
      });
    });

    s3ClientTest(
      'keeps status and body of an error response that is not XML',
      mockResponse: (_) => rawResponse('Bad gateway', status: 502),
      act: (client) => expectLater(
        client.getObject(bucket: 'bucket', key: 'my-key'),
        throwsA(
          isA<S3UnknownException>()
              .having((e) => e.code, 'code', '502')
              .having((e) => e.message, 'message', 'Bad gateway'),
        ),
      ),
    );

    group('parses S3 response documents', () {
      const declaration = '<?xml version="1.0" encoding="UTF-8"?>\n';
      const namespace = 'http://s3.amazonaws.com/doc/2006-03-01/';
      const missingKey = 'The resource you requested does not exist';

      String document(String root, String content) {
        return '$declaration<$root xmlns="$namespace">$content</$root>';
      }

      s3ClientTest(
        'ListBucketResult',
        act: (client) => client.listObjectsV2(bucket: 'bucket').first,
        mockResponse: (_) => rawResponse(
          document(
            'ListBucketResult',
            '<Name>bucket</Name><Prefix/><KeyCount>1</KeyCount>'
                '<MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated>'
                '<Contents><Key>my-image.jpg</Key>'
                '<LastModified>2009-10-12T17:50:30.000Z</LastModified>'
                '<ETag>&quot;fba9dede5f27731c9771645a39863328&quot;</ETag>'
                '<Size>434234</Size><StorageClass>STANDARD</StorageClass>'
                '<Owner><ID>owner-id</ID><DisplayName>owner</DisplayName></Owner>'
                '</Contents>'
                '<CommonPrefixes><Prefix>photos/</Prefix></CommonPrefixes>',
          ),
        ),
        expectResponse: (page) {
          final object = page.contents.single;
          expect(page.name, 'bucket');
          expect(page.prefix, '');
          expect(page.keyCount, 1);
          expect(page.commonPrefixes, ['photos/']);
          expect(object.key, 'my-image.jpg');
          expect(object.eTag, 'fba9dede5f27731c9771645a39863328');
          expect(object.size, 434234);
          expect(object.lastModified, DateTime.utc(2009, 10, 12, 17, 50, 30));
          expect(object.owner?.id, 'owner-id');
          expect(object.owner?.displayName, 'owner');
        },
      );

      s3ClientTest(
        'Error',
        mockResponse: (_) => rawResponse(
          '$declaration<Error><Code>NoSuchKey</Code>'
          '<Message>$missingKey</Message>'
          '<Resource>/bucket/my-key</Resource>'
          '<RequestId>4442587FB7D0A2F9</RequestId></Error>',
          status: 404,
        ),
        act: (client) => expectLater(
          client.getObject(bucket: 'bucket', key: 'my-key'),
          throwsA(
            isA<S3NoSuchKeyException>().having(
              (e) => e.message,
              'message',
              missingKey,
            ),
          ),
        ),
      );

      s3ClientTest(
        'CopyObjectResult',
        act: (client) => client.copyObject(
          bucket: 'bucket',
          key: 'my-key',
          copySource: 'src-bucket/src-key',
        ),
        mockResponse: (_) => rawResponse(
          document(
            'CopyObjectResult',
            '<LastModified>2009-10-28T22:32:00.000Z</LastModified>'
                '<ETag>&quot;9b2cf535f27731c974343645a3985328&quot;</ETag>',
          ),
        ),
        expectResponse: (result) {
          expect(result.eTag, '9b2cf535f27731c974343645a3985328');
          expect(result.lastModified, DateTime.utc(2009, 10, 28, 22, 32));
        },
      );

      s3ClientTest(
        'InitiateMultipartUploadResult',
        act: (client) => client.createMultipartUpload(
          bucket: 'bucket',
          key: 'my-key',
        ),
        mockResponse: (_) => rawResponse(
          document(
            'InitiateMultipartUploadResult',
            '<Bucket>bucket</Bucket><Key>my-key</Key>'
                '<UploadId>VXBsb2FkIElE</UploadId>',
          ),
        ),
        expectResponse: (uploadId) => expect(uploadId, 'VXBsb2FkIElE'),
      );

      s3ClientTest(
        'CompleteMultipartUploadResult',
        act: (client) => client.completeMultipartUpload(
          bucket: 'bucket',
          key: 'my-key',
          uploadId: 'upload-123',
          multipartUpload: const S3CompleteMultipartUpload(parts: []),
        ),
        mockResponse: (_) => rawResponse(
          document(
            'CompleteMultipartUploadResult',
            '<Location>https://bucket.s3.test/my-key</Location>'
                '<Bucket>bucket</Bucket><Key>my-key</Key>'
                '<ETag>&quot;3858f62230ac3c915f300c664312c11f-9&quot;</ETag>',
          ),
        ),
        expectResponse: (result) {
          expect(result.location, 'https://bucket.s3.test/my-key');
          expect(result.eTag, '3858f62230ac3c915f300c664312c11f-9');
        },
      );

      s3ClientTest(
        'DeleteResult',
        act: (client) => client.deleteObjects(
          bucket: 'bucket',
          objects: const [S3ObjectIdentifier(key: 'a')],
        ),
        mockResponse: (_) => rawResponse(
          document(
            'DeleteResult',
            '<Deleted><Key>a</Key><DeleteMarker>true</DeleteMarker>'
                '<DeleteMarkerVersionId>v1</DeleteMarkerVersionId></Deleted>'
                '<Error><Key>b</Key><Code>AccessDenied</Code>'
                '<Message>Access Denied</Message></Error>',
          ),
        ),
        expectResponse: (result) {
          expect(result.deleted.single.key, 'a');
          expect(result.deleted.single.deleteMarker, isTrue);
          expect(result.deleted.single.deleteMarkerVersionId, 'v1');
          expect(result.errors.single.key, 'b');
          expect(result.errors.single.code, 'AccessDenied');
        },
      );

      s3ClientTest(
        'ListPartsResult',
        act: (client) => client
            .listParts(bucket: 'bucket', key: 'my-key', uploadId: 'u')
            .first,
        mockResponse: (_) => rawResponse(
          document(
            'ListPartsResult',
            '<Bucket>bucket</Bucket><Key>my-key</Key><UploadId>u</UploadId>'
                '<PartNumberMarker>1</PartNumberMarker><MaxParts>2</MaxParts>'
                '<IsTruncated>false</IsTruncated>'
                '<Part><PartNumber>2</PartNumber>'
                '<LastModified>2010-11-10T20:48:34.000Z</LastModified>'
                '<ETag>&quot;7778aef83f66abc1fa1e8477f296d394&quot;</ETag>'
                '<Size>10485760</Size></Part>',
          ),
        ),
        expectResponse: (page) {
          expect(page.partNumberMarker, 1);
          expect(page.parts.single.partNumber, 2);
          expect(page.parts.single.eTag, '7778aef83f66abc1fa1e8477f296d394');
          expect(page.parts.single.size, 10485760);
        },
      );
    });

    group('cancellation', () {
      void abortTriggerTest(
        String description,
        Future<void> Function(S3Client client, Context ctx) act,
      ) {
        test(description, () async {
          final mockClient = MockHttpClient();
          Future<void>? abortTrigger;

          when(() => mockClient.send(any())).thenAnswer((invocation) async {
            final request =
                invocation.positionalArguments[0] as http.BaseRequest;
            abortTrigger = (request as http.Abortable).abortTrigger;
            unawaited(request.finalize().drain<void>());
            return emptyResponse(headers: {S3HttpHeaders.etag: '"etag"'});
          });

          final (ctx, cancel) = const Context.empty().withCancel();
          await act(defaultClient(mockClient), ctx);

          var aborted = false;
          unawaited(abortTrigger!.then((_) => aborted = true));
          expect(aborted, isFalse);

          cancel();
          await pumpEventQueue();

          expect(aborted, isTrue);
        });
      }

      abortTriggerTest(
        'uses Context.current when ctx is omitted',
        (client, ctx) => ctx.run(
          () => client.headObject(bucket: 'bucket', key: 'key'),
        ),
      );

      abortTriggerTest(
        'uses explicit ctx',
        (client, ctx) => client.headObject(
          bucket: 'bucket',
          key: 'key',
          ctx: ctx,
        ),
      );

      abortTriggerTest(
        'aborts streamed uploads',
        (client, ctx) => client.putObject(
          bucket: 'bucket',
          key: 'key',
          body: Stream.value(Uint8List.fromList([1])),
          contentLength: 1,
          ctx: ctx,
        ),
      );

      test('throws the context error when the request is aborted', () async {
        final mockClient = MockHttpClient();
        when(() => mockClient.send(any())).thenAnswer(
          (_) async => throw http.RequestAbortedException(),
        );

        final (ctx, cancel) = const Context.empty().withCancel();
        cancel();

        await expectLater(
          defaultClient(mockClient).headObject(
            bucket: 'bucket',
            key: 'key',
            ctx: ctx,
          ),
          throwsA(isA<ContextCancelException>()),
        );
      });
    });
  });
}
