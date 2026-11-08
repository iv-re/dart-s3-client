import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:ctx/ctx.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http;
import 'package:s3_client/src/base_client.dart';
import 'package:s3_client/src/credentials.dart';
import 'package:s3_client/src/error.dart';
import 'package:s3_client/src/model.dart';
import 'package:s3_client/src/request.dart';
import 'package:s3_client/src/sign/signer.dart';
import 'package:xml/xml.dart';

class S3Client extends S3BaseClient {
  S3Client({
    required super.baseEndpoint,
    required S3CredentialsProvider credentials,
    super.usePathStyle = false,
    super.logger,
    String region = 'us-east-1',
    http.Client? httpClient,
  }) : super(
         signer: S3Signer(credentialsProvider: credentials, region: region),
         httpClient: httpClient ?? http.Client(),
       );

  S3Client.aws({
    required String region,
    required S3CredentialsProvider credentials,
    super.logger,
    http.Client? httpClient,
  }) : super(
         signer: S3Signer(credentialsProvider: credentials, region: region),
         httpClient: httpClient ?? http.Client(),
         baseEndpoint: Uri.parse('https://s3.$region.amazonaws.com'),
         usePathStyle: false,
       );

  S3Client.r2({
    required String accountId,
    required S3CredentialsProvider credentials,
    super.logger,
    http.Client? httpClient,
  }) : super(
         signer: S3Signer(credentialsProvider: credentials, region: 'auto'),
         httpClient: httpClient ?? http.Client(),
         baseEndpoint: Uri.parse('https://$accountId.r2.cloudflarestorage.com'),
         usePathStyle: false,
       );

  Future<S3ObjectStream> getObject({
    required String bucket,
    required String key,
    String? range,
    String? versionId,
    String? ifMatch,
    String? ifNoneMatch,
    DateTime? ifModifiedSince,
    DateTime? ifUnmodifiedSince,
    Context? ctx,
  }) async {
    final response = await request(
      'GET',
      bucket: bucket,
      key: key,
      queryParameters: {'versionId': ?versionId},
      headers: {
        S3HttpHeaders.range: ?range,
        S3HttpHeaders.ifMatch: ?ifMatch,
        S3HttpHeaders.ifNoneMatch: ?ifNoneMatch,
        S3HttpHeaders.ifModifiedSince: ?ifModifiedSince != null
            ? http.formatHttpDate(ifModifiedSince)
            : null,
        S3HttpHeaders.ifUnmodifiedSince: ?ifUnmodifiedSince != null
            ? http.formatHttpDate(ifUnmodifiedSince)
            : null,
      },
      ctx: ctx,
    );

    final headers = response.headers;

    return S3ObjectStream(
      body: response.stream,
      contentLength: response.contentLength,
      contentType: headers[S3HttpHeaders.contentType],
      eTag: headers[S3HttpHeaders.etag] != null
          ? S3Etag.parse(headers[S3HttpHeaders.etag]!)
          : null,
      lastModified: headers[S3HttpHeaders.lastModified] != null
          ? http.parseHttpDate(headers[S3HttpHeaders.lastModified]!)
          : null,
      versionId: headers[S3HttpHeaders.versionId],
      deleteMarker: headers[S3HttpHeaders.deleteMarker] == 'true',
      metadata: S3Metadata.fromHeaders(headers),
      storageClass: headers[S3HttpHeaders.storageClass],
      acceptRanges: headers[S3HttpHeaders.acceptRanges],
    );
  }

  Future<S3PutObjectResult> putObject({
    required String bucket,
    required String key,
    required Stream<Uint8List> body,
    String? contentType,
    String? contentDisposition,
    String? contentEncoding,
    String? contentLanguage,
    String? cacheControl,
    DateTime? expires,
    int? contentLength,
    Map<String, String>? metadata,
    S3ObjectAcl? acl,
    Map<String, String>? tagging,
    String? storageClass,
    String? ifMatch,
    String? ifNoneMatch,
    Context? ctx,
  }) async {
    final response = await request(
      'PUT',
      bucket: bucket,
      key: key,
      headers: {
        S3HttpHeaders.contentType: ?contentType,
        S3HttpHeaders.contentDisposition: ?contentDisposition,
        S3HttpHeaders.contentEncoding: ?contentEncoding,
        S3HttpHeaders.contentLanguage: ?contentLanguage,
        S3HttpHeaders.cacheControl: ?cacheControl,
        S3HttpHeaders.expires: ?expires != null
            ? http.formatHttpDate(expires)
            : null,
        ...?metadata?.map((k, v) => MapEntry('x-amz-meta-$k', v)),
        S3HttpHeaders.acl: ?acl?.headerValue,
        S3HttpHeaders.storageClass: ?storageClass,
        S3HttpHeaders.tagging: ?tagging?.toS3TaggingHeader(),
        S3HttpHeaders.ifMatch: ?ifMatch,
        S3HttpHeaders.ifNoneMatch: ?ifNoneMatch,
      },
      body: .stream(body, contentLength: contentLength),
      ctx: ctx,
    );

    return S3PutObjectResult(
      eTag: S3Etag.parse(response.headers[S3HttpHeaders.etag]!),
      versionId: response.headers[S3HttpHeaders.versionId],
    );
  }

  Future<S3HeadObjectResult> headObject({
    required String bucket,
    required String key,
    String? versionId,
    int? partNumber,
    String? ifMatch,
    String? ifNoneMatch,
    DateTime? ifModifiedSince,
    DateTime? ifUnmodifiedSince,
    Context? ctx,
  }) async {
    try {
      final response = await request(
        'HEAD',
        bucket: bucket,
        key: key,
        queryParameters: {
          'versionId': ?versionId,
          'partNumber': ?partNumber?.toString(),
        },
        headers: {
          S3HttpHeaders.ifMatch: ?ifMatch,
          S3HttpHeaders.ifNoneMatch: ?ifNoneMatch,
          S3HttpHeaders.ifModifiedSince: ?ifModifiedSince != null
              ? http.formatHttpDate(ifModifiedSince)
              : null,
          S3HttpHeaders.ifUnmodifiedSince: ?ifUnmodifiedSince != null
              ? http.formatHttpDate(ifUnmodifiedSince)
              : null,
        },
        ctx: ctx,
      );

      return S3HeadObjectResult.fromHeaders(response.headers);
    } on S3UnknownException catch (error, stackTrace) {
      if (error.code == '404') throw S3NoSuchKeyException(error.message);

      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> deleteObject({
    required String bucket,
    required String key,
    String? versionId,
    Context? ctx,
  }) async {
    await request(
      'DELETE',
      bucket: bucket,
      key: key,
      queryParameters: {'versionId': ?versionId},
      ctx: ctx,
    );
  }

  Future<S3CopyObjectResult> copyObject({
    required String bucket,
    required String key,
    required String copySource,
    String? copySourceVersionId,
    S3MetadataDirective metadataDirective = .copy,
    Map<String, String>? metadata,
    String? contentType,
    String? contentDisposition,
    String? contentEncoding,
    String? contentLanguage,
    String? cacheControl,
    DateTime? expires,
    String? copySourceIfMatch,
    String? copySourceIfNoneMatch,
    DateTime? copySourceIfModifiedSince,
    DateTime? copySourceIfUnmodifiedSince,
    S3ObjectAcl? acl,
    Map<String, String>? tagging,
    String? storageClass,
    Context? ctx,
  }) async {
    final response = await request(
      'PUT',
      bucket: bucket,
      key: key,
      headers: {
        S3HttpHeaders.copySource: _encodeCopySource(
          copySource,
          versionId: copySourceVersionId,
        ),
        S3HttpHeaders.contentType: ?contentType,
        S3HttpHeaders.contentDisposition: ?contentDisposition,
        S3HttpHeaders.contentEncoding: ?contentEncoding,
        S3HttpHeaders.contentLanguage: ?contentLanguage,
        S3HttpHeaders.cacheControl: ?cacheControl,
        S3HttpHeaders.expires: ?expires != null
            ? http.formatHttpDate(expires)
            : null,
        S3HttpHeaders.copySourceIfMatch: ?copySourceIfMatch,
        S3HttpHeaders.copySourceIfNoneMatch: ?copySourceIfNoneMatch,
        S3HttpHeaders.copySourceIfModifiedSince:
            ?copySourceIfModifiedSince != null
            ? http.formatHttpDate(copySourceIfModifiedSince)
            : null,
        S3HttpHeaders.copySourceIfUnmodifiedSince:
            ?copySourceIfUnmodifiedSince != null
            ? http.formatHttpDate(copySourceIfUnmodifiedSince)
            : null,
        if (metadataDirective == .replace) ...{
          S3HttpHeaders.metadataDirective: 'REPLACE',
          ...?metadata?.map((k, v) => MapEntry('x-amz-meta-$k', v)),
        },
        S3HttpHeaders.acl: ?acl?.headerValue,
        S3HttpHeaders.storageClass: ?storageClass,
        S3HttpHeaders.tagging: ?tagging?.toS3TaggingHeader(),
        if (tagging != null) S3HttpHeaders.taggingDirective: 'REPLACE',
      },
      ctx: ctx,
    );

    final body = await response.stream.bytesToString();
    _throwIfEmbeddedError(body);

    return S3CopyObjectResult.fromXmlDocument(
      body,
      versionId: response.headers[S3HttpHeaders.versionId],
      copySourceVersionId: response.headers[S3HttpHeaders.copySourceVersionId],
    );
  }

  Stream<S3ListObjectsResult> listObjectsV2({
    required String bucket,
    String? prefix,
    String? delimiter,
    int? maxKeys,
    String? startAfter,
    Context? ctx,
  }) async* {
    String? continuationToken;
    var isTruncated = false;

    do {
      final response = await request(
        'GET',
        bucket: bucket,
        queryParameters: {
          'list-type': '2',
          'continuation-token': ?continuationToken,
          'prefix': ?prefix,
          'delimiter': ?delimiter,
          'max-keys': ?maxKeys?.toString(),
          'start-after': ?startAfter,
        },
        ctx: ctx,
      );

      final body = await response.stream.bytesToString();
      final page = S3ListObjectsResult.fromXmlDocument(body);

      yield page;

      isTruncated = page.isTruncated;
      continuationToken = page.nextContinuationToken;
    } while (isTruncated && continuationToken != null);
  }

  Stream<S3ListObjectVersionsResult> listObjectVersions({
    required String bucket,
    String? prefix,
    String? delimiter,
    int? maxKeys,
    Context? ctx,
  }) async* {
    String? keyMarker;
    String? versionIdMarker;
    var isTruncated = false;

    do {
      final response = await request(
        'GET',
        bucket: bucket,
        queryParameters: {
          'versions': '',
          'prefix': ?prefix,
          'delimiter': ?delimiter,
          'max-keys': ?maxKeys?.toString(),
          'key-marker': ?keyMarker,
          'version-id-marker': ?versionIdMarker,
        },
        ctx: ctx,
      );

      final body = await response.stream.bytesToString();
      final page = S3ListObjectVersionsResult.fromXmlDocument(body);

      yield page;

      keyMarker = page.nextKeyMarker;
      versionIdMarker = page.nextVersionIdMarker;
      isTruncated = page.isTruncated;
    } while (isTruncated && (keyMarker != null || versionIdMarker != null));
  }

  Future<S3DeleteObjectsResult> deleteObjects({
    required String bucket,
    required List<S3ObjectIdentifier> objects,
    bool quiet = false,
    Context? ctx,
  }) async {
    const maxKeys = 1000;
    final deleted = <S3DeletedObject>[];
    final errors = <S3Error>[];

    for (var i = 0; i < objects.length; i += maxKeys) {
      final end = (i + maxKeys < objects.length) ? i + maxKeys : objects.length;
      final chunk = objects.sublist(i, end);
      final result = await _deleteObjectsChunk(
        bucket: bucket,
        delete: S3Delete(objects: chunk, quiet: quiet),
        ctx: ctx,
      );
      deleted.addAll(result.deleted);
      errors.addAll(result.errors);
    }

    return S3DeleteObjectsResult(deleted: deleted, errors: errors);
  }

  Future<S3DeleteObjectsResult> _deleteObjectsChunk({
    required String bucket,
    required S3Delete delete,
    Context? ctx,
  }) async {
    final body = utf8.encode(delete.toXml().toXmlString());
    final md5Digest = base64Encode(md5.convert(body).bytes);

    final response = await request(
      'POST',
      bucket: bucket,
      queryParameters: {'delete': ''},
      headers: {S3HttpHeaders.contentMd5: md5Digest},
      body: S3RequestBody.bytes(Uint8List.fromList(body)),
      ctx: ctx,
    );

    final responseBody = await response.stream.bytesToString();
    return S3DeleteObjectsResult.fromXmlDocument(responseBody);
  }

  Future<Uri> presignGetObject({
    required String bucket,
    required String key,
    String? versionId,
    Duration expires = const Duration(minutes: 15),
  }) {
    return presign(
      'GET',
      bucket: bucket,
      key: key,
      expires: expires,
      queryParameters: {'versionId': ?versionId},
    );
  }

  Future<Uri> presignPutObject({
    required String bucket,
    required String key,
    Duration expires = const Duration(minutes: 15),
  }) {
    return presign('PUT', bucket: bucket, key: key, expires: expires);
  }

  Future<S3UploadId> createMultipartUpload({
    required String bucket,
    required String key,
    String? contentType,
    String? contentDisposition,
    String? contentEncoding,
    String? contentLanguage,
    String? cacheControl,
    DateTime? expires,
    Map<String, String>? metadata,
    S3ObjectAcl? acl,
    Map<String, String>? tagging,
    String? storageClass,
    Context? ctx,
  }) async {
    final response = await request(
      'POST',
      bucket: bucket,
      key: key,
      queryParameters: {'uploads': ''},
      headers: {
        S3HttpHeaders.contentType: ?contentType,
        S3HttpHeaders.contentDisposition: ?contentDisposition,
        S3HttpHeaders.contentEncoding: ?contentEncoding,
        S3HttpHeaders.contentLanguage: ?contentLanguage,
        S3HttpHeaders.cacheControl: ?cacheControl,
        S3HttpHeaders.expires: ?expires != null
            ? http.formatHttpDate(expires)
            : null,
        ...?metadata?.map((k, v) => MapEntry('x-amz-meta-$k', v)),
        S3HttpHeaders.acl: ?acl?.headerValue,
        S3HttpHeaders.storageClass: ?storageClass,
        S3HttpHeaders.tagging: ?tagging?.toS3TaggingHeader(),
      },
      ctx: ctx,
    );

    final body = await response.stream.bytesToString();
    return S3UploadId.fromXmlDocument(body);
  }

  Future<S3Etag> uploadPart({
    required String bucket,
    required String key,
    required String uploadId,
    required int partNumber,
    required Stream<Uint8List> body,
    int? contentLength,
    Context? ctx,
  }) async {
    final response = await request(
      'PUT',
      bucket: bucket,
      key: key,
      queryParameters: {
        'uploadId': uploadId,
        'partNumber': partNumber.toString(),
      },
      body: S3RequestBody.stream(body, contentLength: contentLength),
      ctx: ctx,
    );

    return S3Etag.parse(response.headers[S3HttpHeaders.etag]!);
  }

  Future<S3CopyPartResult> uploadPartCopy({
    required String bucket,
    required String key,
    required String uploadId,
    required int partNumber,
    required String copySource,
    String? copySourceVersionId,
    String? copySourceRange,
    String? copySourceIfMatch,
    String? copySourceIfNoneMatch,
    DateTime? copySourceIfModifiedSince,
    DateTime? copySourceIfUnmodifiedSince,
    Context? ctx,
  }) async {
    final response = await request(
      'PUT',
      bucket: bucket,
      key: key,
      queryParameters: {
        'partNumber': partNumber.toString(),
        'uploadId': uploadId,
      },
      headers: {
        S3HttpHeaders.copySource: _encodeCopySource(
          copySource,
          versionId: copySourceVersionId,
        ),
        S3HttpHeaders.copySourceRange: ?copySourceRange,
        S3HttpHeaders.copySourceIfMatch: ?copySourceIfMatch,
        S3HttpHeaders.copySourceIfNoneMatch: ?copySourceIfNoneMatch,
        S3HttpHeaders.copySourceIfModifiedSince:
            ?copySourceIfModifiedSince != null
            ? http.formatHttpDate(copySourceIfModifiedSince)
            : null,
        S3HttpHeaders.copySourceIfUnmodifiedSince:
            ?copySourceIfUnmodifiedSince != null
            ? http.formatHttpDate(copySourceIfUnmodifiedSince)
            : null,
      },
      ctx: ctx,
    );

    final body = await response.stream.bytesToString();
    _throwIfEmbeddedError(body);

    return S3CopyPartResult.fromXmlDocument(body);
  }

  Future<S3CompleteMultipartUploadResult> completeMultipartUpload({
    required String bucket,
    required String key,
    required String uploadId,
    required S3CompleteMultipartUpload multipartUpload,
    String? ifMatch,
    String? ifNoneMatch,
    Context? ctx,
  }) async {
    final response = await request(
      'POST',
      bucket: bucket,
      key: key,
      queryParameters: {'uploadId': uploadId},
      headers: {
        S3HttpHeaders.ifMatch: ?ifMatch,
        S3HttpHeaders.ifNoneMatch: ?ifNoneMatch,
      },
      body: S3RequestBody.bytes(
        Uint8List.fromList(utf8.encode(multipartUpload.toXml().toXmlString())),
      ),
      ctx: ctx,
    );

    final body = await response.stream.bytesToString();
    _throwIfEmbeddedError(body);

    final versionId = response.headers[S3HttpHeaders.versionId];

    return S3CompleteMultipartUploadResult.fromXmlDocument(
      body,
      versionId: versionId,
    );
  }

  Future<void> abortMultipartUpload({
    required String bucket,
    required String key,
    required String uploadId,
    Context? ctx,
  }) async {
    await request(
      'DELETE',
      bucket: bucket,
      key: key,
      queryParameters: {'uploadId': uploadId},
      ctx: ctx,
    );
  }

  Stream<S3ListPartsResult> listParts({
    required String bucket,
    required String key,
    required String uploadId,
    int? maxParts,
    Context? ctx,
  }) async* {
    int? partNumberMarker;
    var isTruncated = false;

    do {
      final response = await request(
        'GET',
        bucket: bucket,
        key: key,
        queryParameters: {
          'uploadId': uploadId,
          'max-parts': ?maxParts?.toString(),
          'part-number-marker': ?partNumberMarker?.toString(),
        },
        ctx: ctx,
      );

      final body = await response.stream.bytesToString();
      final page = S3ListPartsResult.fromXmlDocument(body);

      yield page;

      partNumberMarker = page.nextPartNumberMarker;
      isTruncated = page.isTruncated;
    } while (isTruncated && partNumberMarker != null);
  }

  Stream<S3ListMultipartUploadsResult> listMultipartUploads({
    required String bucket,
    String? prefix,
    String? delimiter,
    int? maxUploads,
    Context? ctx,
  }) async* {
    String? keyMarker;
    String? uploadIdMarker;
    var isTruncated = false;

    do {
      final response = await request(
        'GET',
        bucket: bucket,
        queryParameters: {
          'uploads': '',
          'prefix': ?prefix,
          'delimiter': ?delimiter,
          'max-uploads': ?maxUploads?.toString(),
          'key-marker': ?keyMarker,
          'upload-id-marker': ?uploadIdMarker,
        },
        ctx: ctx,
      );

      final body = await response.stream.bytesToString();
      final page = S3ListMultipartUploadsResult.fromXmlDocument(body);

      yield page;

      keyMarker = page.nextKeyMarker;
      uploadIdMarker = page.nextUploadIdMarker;
      isTruncated = page.isTruncated;
    } while (isTruncated && (keyMarker != null || uploadIdMarker != null));
  }
}

extension on Map<String, String> {
  String? toS3TaggingHeader() {
    if (isEmpty) return null;

    return entries
        .map(
          (entry) {
            final encodedKey = Uri.encodeQueryComponent(entry.key);
            final encodedValue = Uri.encodeQueryComponent(entry.value);

            return '$encodedKey=$encodedValue';
          },
        )
        .join('&');
  }
}

String _encodeCopySource(String copySource, {String? versionId}) {
  final encoded = copySource.split('/').map(Uri.encodeComponent).join('/');
  if (versionId == null) return encoded;

  return '$encoded?versionId=${Uri.encodeComponent(versionId)}';
}

/// Throws the error S3 reported in the body of a `200 OK` response.
///
/// Copy and complete multipart upload requests can fail after S3 has already
/// sent a successful status.
void _throwIfEmbeddedError(String body) {
  final root = XmlDocument.parse(body).rootElement;
  if (root.name.local == 'Error') {
    throw S3Exception.fromError(S3Error.fromXml(root));
  }
}
