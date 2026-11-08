import 'dart:typed_data';

import 'package:ctx/ctx.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

typedef S3BaseRequest = http.BaseRequest;

class S3Request(
  super.method,
  super.url, {
  final Context? _ctx,
}) extends http.Request with http.Abortable {
  @override
  Future<void>? get abortTrigger => _ctx?.done;
}

class S3StreamedRequest(
  super.method,
  super.url, {
  final Context? _ctx,
}) extends http.StreamedRequest with http.Abortable {
  @override
  Future<void>? get abortTrigger => _ctx?.done;
}

sealed class S3RequestBody {
  const factory S3RequestBody.bytes(
    Uint8List bytes,
  ) = S3RequestBodyBytes;

  const factory S3RequestBody.stream(
    Stream<Uint8List> bytes, {
    int? contentLength,
  }) = S3RequestBodyStream;
}

class const S3RequestBodyBytes(final Uint8List bytes) implements S3RequestBody;

class const S3RequestBodyStream(
  final Stream<Uint8List> stream, {
  final int? contentLength,
}) implements S3RequestBody;

@internal
abstract final class S3HttpHeaders {
  static const date = 'x-amz-date';
  static const contentSha256 = 'x-amz-content-sha256';
  static const host = 'host';
  static const authorization = 'authorization';
  static const securityToken = 'x-amz-security-token';
  static const userAgent = 'user-agent';
  static const copySource = 'x-amz-copy-source';
  static const metadataDirective = 'x-amz-metadata-directive';
  static const range = 'Range';
  static const ifMatch = 'If-Match';
  static const ifNoneMatch = 'If-None-Match';
  static const ifModifiedSince = 'If-Modified-Since';
  static const ifUnmodifiedSince = 'If-Unmodified-Since';
  static const etag = 'etag';
  static const contentType = 'content-type';
  static const contentLength = 'content-length';
  static const lastModified = 'last-modified';
  static const versionId = 'x-amz-version-id';
  static const copySourceVersionId = 'x-amz-copy-source-version-id';
  static const copySourceIfMatch = 'x-amz-copy-source-if-match';
  static const copySourceIfNoneMatch = 'x-amz-copy-source-if-none-match';
  static const copySourceIfModifiedSince =
      'x-amz-copy-source-if-modified-since';
  static const copySourceIfUnmodifiedSince =
      'x-amz-copy-source-if-unmodified-since';
  static const contentMd5 = 'content-md5';
  static const copySourceRange = 'x-amz-copy-source-range';
  static const cacheControl = 'cache-control';
  static const contentDisposition = 'content-disposition';
  static const contentEncoding = 'content-encoding';
  static const contentLanguage = 'content-language';
  static const expires = 'expires';
  static const acceptRanges = 'accept-ranges';
  static const acl = 'x-amz-acl';
  static const tagging = 'x-amz-tagging';
  static const taggingDirective = 'x-amz-tagging-directive';
  static const storageClass = 'x-amz-storage-class';
  static const deleteMarker = 'x-amz-delete-marker';
  static const restore = 'x-amz-restore';
}

@internal
abstract final class S3QueryParams {
  static const algorithm = 'X-Amz-Algorithm';
  static const credential = 'X-Amz-Credential';
  static const date = 'X-Amz-Date';
  static const expires = 'X-Amz-Expires';
  static const signedHeaders = 'X-Amz-SignedHeaders';
  static const signature = 'X-Amz-Signature';
  static const securityToken = 'X-Amz-Security-Token';
}
