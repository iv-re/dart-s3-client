import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:s3_client/s3_client.dart';
import 'package:s3_client/src/request.dart';
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

  void s3ClientTest<T>(
    String description, {
    required FutureOr<T> Function(S3Client client) act,
    S3Client Function(http.Client httpClient)? build,
    http.StreamedResponse Function(http.BaseRequest request)? mockResponse,
    FutureOr<void> Function(http.BaseRequest request)? expectRequest,
    FutureOr<void> Function(List<http.BaseRequest> requests)? expectRequests,
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

      when(() => mockHttpClient.send(any())).thenAnswer(
        (invocation) async {
          final request = invocation.positionalArguments[0] as http.BaseRequest;
          unawaited(request.finalize().drain());
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
        const S3ListObjectsResult(
          name: 'bucket',
          prefix: 'folder/',
          maxKeys: 50,
          isTruncated: false,
          keyCount: 0,
          contents: [],
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
      },
    );

    test('presignGetObject generates correct URL', () async {
      final s3client = defaultClient(MockHttpClient());
      final uri = await s3client.presignGetObject(
        bucket: 'bucket',
        key: 'my-key',
        versionId: 'my-version-id',
      );
      expect(
        uri.toString(),
        contains('https://bucket.s3.test/my-key'),
      );
      expect(
        uri.queryParameters['versionId'],
        'my-version-id',
      );
    });

    test('presignPutObject generates correct URL', () async {
      final s3client = defaultClient(MockHttpClient());
      final uri = await s3client.presignPutObject(
        bucket: 'bucket',
        key: 'my-key',
      );
      expect(
        uri.toString(),
        contains('https://bucket.s3.test/my-key'),
      );
    });

    s3ClientTest(
      'putObject uploads data and returns ETag',
      act: (client) => client.putObject(
        bucket: 'bucket',
        key: 'my-key',
        body: Stream.value(Uint8List.fromList([1, 2, 3])),
        contentType: 'application/octet-stream',
        contentLength: 3,
        metadata: {'custom': 'value'},
        acl: S3ObjectAcl.publicRead,
        tagging: {'key1': 'val1', 'key2': 'val2'},
        storageClass: 'EXPRESS_ONEZONE',
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
        expect(req.headers['x-amz-meta-custom'], 'value');
        expect(req.headers[S3HttpHeaders.acl], 'public-read');
        expect(req.headers[S3HttpHeaders.tagging], 'key1=val1&key2=val2');
        expect(req.headers[S3HttpHeaders.storageClass], 'EXPRESS_ONEZONE');
      },
      expectResponse: (result) {
        expect(result.eTag, 'mock-etag');
        expect(result.versionId, 'version-123');
      },
    );

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

    s3ClientTest(
      'copyObject copies object',
      act: (client) => client.copyObject(
        bucket: 'bucket',
        key: 'my-key',
        copySource: 'src-bucket/src-key with spaces/i+s.txt/literal%2Bpercent',
        contentType: 'text/plain',
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
        expect(req.headers[S3HttpHeaders.metadataDirective], 'REPLACE');
        expect(req.headers['x-amz-meta-custom'], 'new-val');
        expect(req.headers[S3HttpHeaders.acl], 'public-read');
        expect(req.headers[S3HttpHeaders.tagging], 'copied=true');
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
      'createMultipartUpload initiates upload',
      act: (client) => client.createMultipartUpload(
        bucket: 'bucket',
        key: 'my-key',
        contentType: 'text/plain',
        metadata: {'custom': 'value'},
        acl: S3ObjectAcl.private,
        tagging: {'project': 'pusk'},
        storageClass: 'GLACIER_IR',
      ),
      mockResponse: (_) => xmlResponse(S3UploadId('upload-123').toXml()),
      expectRequest: (req) {
        expect(
          req.url.toString(),
          'https://bucket.s3.test/my-key?uploads',
        );
        expect(req.method, 'POST');
        expect(req.headers[S3HttpHeaders.contentType], 'text/plain');
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
            S3CompletedPart(partNumber: 1, eTag: S3Etag('etag-1')),
          ],
        ),
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
        expect(req.headers.containsKey(S3HttpHeaders.contentMd5), isTrue);
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
        expect(requests.length, 2);
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
      expectResponse: (pages) {
        expect(pages.length, 2);
      },
    );
  });
}
