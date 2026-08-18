import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http_parser/http_parser.dart' as http;
import 'package:s3_client/src/request.dart';
import 'package:xml/xml.dart';

class S3ObjectStream({
  required Stream<List<int>> body,
  required final int? contentLength,
  required final String? contentType,
  final S3Etag? eTag,
  final DateTime? lastModified,
  final String? versionId,
  final bool? deleteMarker,
  final Map<String, String> metadata = const {},
  final String? storageClass,
  final String? acceptRanges,
}) extends StreamView<Uint8List> {
  this : super(body.cast<Uint8List>());

  /// Collects the data of this stream in a [Uint8List].
  Future<Uint8List> toBytes() async {
    final builder = BytesBuilder(copy: false);
    await forEach(builder.add);
    return builder.takeBytes();
  }

  /// Collect the data of this stream in a [String], decoded according to
  /// [encoding], which defaults to `UTF8`.
  Future<String> bytesToString([Encoding encoding = utf8]) {
    return encoding.decodeStream(this);
  }
}

extension type const S3Etag(String value) implements String {
  /// Strips surrounding quotes S3 wraps ETags in (`"abc123"` → `abc123`).
  factory S3Etag.parse(String raw) {
    return S3Etag(raw.replaceAll('"', ''));
  }
}

class const S3Owner({
  required final String id,
  final String? displayName,
}) {
  factory S3Owner.fromXml(XmlElement element) {
    return S3Owner(
      id: element.str('ID'),
      displayName: element.strOrNull('DisplayName'),
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element('ID', nest: id);
    if (displayName != null) {
      builder.element('DisplayName', nest: displayName);
    }
    return builder.buildDocument();
  }
}

class const S3Initiator({
  required final String id,
  final String? displayName,
}) {
  factory S3Initiator.fromXml(XmlElement element) {
    return S3Initiator(
      id: element.str('ID'),
      displayName: element.strOrNull('DisplayName'),
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element('ID', nest: id);
    if (displayName != null) {
      builder.element('DisplayName', nest: displayName);
    }
    return builder.buildDocument();
  }
}

class const S3Object({
  required final String key,
  required final S3Etag eTag,
  required final int size,
  required final String storageClass,
  required final DateTime lastModified,
  final S3Owner? owner,
}) {
  factory S3Object.fromXml(XmlElement element) {
    final ownerElement = element.getElement('Owner');
    return S3Object(
      key: element.str('Key'),
      eTag: S3Etag.parse(element.str('ETag')),
      size: element.integer('Size'),
      storageClass: element.str('StorageClass'),
      lastModified: element.dateTime('LastModified'),
      owner: ownerElement != null ? S3Owner.fromXml(ownerElement) : null,
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder()
      ..element('Key', nest: key)
      ..element('ETag', nest: '"$eTag"')
      ..element('Size', nest: size)
      ..element('StorageClass', nest: storageClass)
      ..element('LastModified', nest: lastModified.toUtc().toIso8601String());
    if (owner case final owner?) {
      builder.element('Owner', nest: owner.toXml().children);
    }

    return builder.buildDocument();
  }
}

class const S3ListObjectsResult({
  required final String name,
  required final String prefix,
  required final int maxKeys,
  required final bool isTruncated,
  required final int keyCount,
  required final List<S3Object> contents,
  final List<String> commonPrefixes = const [],
  final String? nextContinuationToken,
  final String? delimiter,
  final String? encodingType,
  final String? continuationToken,
  final String? startAfter,
}) {
  factory S3ListObjectsResult.fromXml(XmlElement element) {
    return S3ListObjectsResult(
      name: element.str('Name'),
      prefix: element.strOrNull('Prefix') ?? '',
      maxKeys: element.integer('MaxKeys'),
      isTruncated: element.boolean('IsTruncated'),
      keyCount: element.integerOrNull('KeyCount') ?? 0,
      contents: element
          .findElements('Contents')
          .map(S3Object.fromXml)
          .toList(growable: false),
      commonPrefixes: element
          .findElements('CommonPrefixes')
          .map((e) => e.str('Prefix'))
          .toList(growable: false),
      nextContinuationToken: element.strOrNull('NextContinuationToken'),
      delimiter: element.strOrNull('Delimiter'),
      encodingType: element.strOrNull('EncodingType'),
      continuationToken: element.strOrNull('ContinuationToken'),
      startAfter: element.strOrNull('StartAfter'),
    );
  }

  factory S3ListObjectsResult.fromXmlDocument(String xml) {
    return S3ListObjectsResult.fromXml(
      XmlDocument.parse(xml).findElements('ListBucketResult').first,
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element(
      'ListBucketResult',
      nest: () {
        builder.element('Name', nest: name);
        builder.element('Prefix', nest: prefix);
        builder.element('MaxKeys', nest: maxKeys);
        builder.element('IsTruncated', nest: isTruncated.toString());
        builder.element('KeyCount', nest: keyCount);
        for (final c in contents) {
          builder.element('Contents', nest: c.toXml().children);
        }
        for (final p in commonPrefixes) {
          builder.element(
            'CommonPrefixes',
            nest: () {
              builder.element('Prefix', nest: p);
            },
          );
        }
        if (nextContinuationToken != null) {
          builder.element('NextContinuationToken', nest: nextContinuationToken);
        }
        if (delimiter != null) {
          builder.element('Delimiter', nest: delimiter);
        }
        if (encodingType != null) {
          builder.element('EncodingType', nest: encodingType);
        }
        if (continuationToken != null) {
          builder.element('ContinuationToken', nest: continuationToken);
        }
        if (startAfter != null) {
          builder.element('StartAfter', nest: startAfter);
        }
      },
    );
    return builder.buildDocument();
  }
}

class const S3Error({
  required final String code,
  required final String message,
  final String? key,
  final String? versionId,
  final String? requestId,
  final String? hostId,
}) {
  factory S3Error.fromXml(XmlElement element) {
    return S3Error(
      code: element.str('Code'),
      message: element.str('Message'),
      key: element.strOrNull('Key'),
      versionId: element.strOrNull('VersionId'),
      requestId: element.strOrNull('RequestId'),
      hostId: element.strOrNull('HostId'),
    );
  }

  factory S3Error.fromXmlDocument(String xml) {
    return S3Error.fromXml(
      XmlDocument.parse(xml).findElements('Error').first,
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder();
    if (key != null) builder.element('Key', nest: key);
    builder.element('Code', nest: code);
    builder.element('Message', nest: message);
    if (versionId != null) {
      builder.element('VersionId', nest: versionId);
    }
    if (requestId != null) {
      builder.element('RequestId', nest: requestId);
    }
    if (hostId != null) {
      builder.element('HostId', nest: hostId);
    }
    return builder.buildDocument();
  }
}

class const S3HeadObjectResult({
  required final int? contentLength,
  required final String? contentType,
  required final S3Etag? eTag,
  required final DateTime? lastModified,
  final Map<String, String> metadata = const {},
  final String? versionId,
  final bool? deleteMarker,
  final String? storageClass,
  final String? restore,
  final String? cacheControl,
  final String? contentDisposition,
  final String? contentEncoding,
  final String? contentLanguage,
  final DateTime? expires,
  final String? acceptRanges,
}) {
  factory S3HeadObjectResult.fromHeaders(Map<String, String> headers) {
    return S3HeadObjectResult(
      contentLength: int.tryParse(headers[S3HttpHeaders.contentLength] ?? ''),
      contentType: headers[S3HttpHeaders.contentType],
      eTag: headers[S3HttpHeaders.etag] != null
          ? S3Etag.parse(headers[S3HttpHeaders.etag]!)
          : null,
      lastModified: headers[S3HttpHeaders.lastModified] != null
          ? http.parseHttpDate(headers[S3HttpHeaders.lastModified]!)
          : null,
      metadata: S3Metadata.fromHeaders(headers),
      versionId: headers[S3HttpHeaders.versionId],
      deleteMarker: headers[S3HttpHeaders.deleteMarker] == 'true',
      storageClass: headers[S3HttpHeaders.storageClass],
      restore: headers[S3HttpHeaders.restore],
      cacheControl: headers[S3HttpHeaders.cacheControl],
      contentDisposition: headers[S3HttpHeaders.contentDisposition],
      contentEncoding: headers[S3HttpHeaders.contentEncoding],
      contentLanguage: headers[S3HttpHeaders.contentLanguage],
      expires: headers[S3HttpHeaders.expires] != null
          ? http.parseHttpDate(headers[S3HttpHeaders.expires]!)
          : null,
      acceptRanges: headers[S3HttpHeaders.acceptRanges],
    );
  }
}

enum S3MetadataDirective { copy, replace }

class const S3PutObjectResult({
  required final S3Etag eTag,
  final String? versionId,
});

class const S3CopyObjectResult({
  required final S3Etag eTag,
  required final DateTime lastModified,
  final String? versionId,
  final String? copySourceVersionId,
}) {
  factory S3CopyObjectResult.fromXml(
    XmlElement element, {
    String? versionId,
    String? copySourceVersionId,
  }) {
    return S3CopyObjectResult(
      eTag: S3Etag.parse(element.str('ETag')),
      lastModified: element.dateTime('LastModified'),
      versionId: versionId,
      copySourceVersionId: copySourceVersionId,
    );
  }

  factory S3CopyObjectResult.fromXmlDocument(
    String xml, {
    String? versionId,
    String? copySourceVersionId,
  }) {
    return S3CopyObjectResult.fromXml(
      XmlDocument.parse(xml).findElements('CopyObjectResult').first,
      versionId: versionId,
      copySourceVersionId: copySourceVersionId,
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element(
      'CopyObjectResult',
      nest: () {
        builder.element('ETag', nest: '"$eTag"');
        builder.element(
          'LastModified',
          nest: lastModified.toUtc().toIso8601String(),
        );
      },
    );
    return builder.buildDocument();
  }
}

extension type const S3UploadId(String value) implements String {
  factory S3UploadId.fromXml(XmlElement element) {
    return S3UploadId(element.str('UploadId'));
  }

  factory S3UploadId.fromXmlDocument(String xml) {
    return S3UploadId.fromXml(
      XmlDocument.parse(
        xml,
      ).findElements('InitiateMultipartUploadResult').first,
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element(
      'InitiateMultipartUploadResult',
      nest: () {
        builder.element('UploadId', nest: value);
      },
    );
    return builder.buildDocument();
  }
}

class const S3CompletedPart({
  required final int partNumber,
  required final S3Etag eTag,
}) {
  XmlNode toXml() {
    final builder = XmlBuilder()
      ..element('PartNumber', nest: partNumber)
      ..element('ETag', nest: '"$eTag"');
    return builder.buildDocument();
  }
}

class const S3CompleteMultipartUpload({
  required final List<S3CompletedPart> parts,
}) {
  XmlNode toXml() {
    final sortedParts = List<S3CompletedPart>.from(parts)
      ..sort((a, b) => a.partNumber.compareTo(b.partNumber));

    final builder = XmlBuilder();
    builder.element(
      'CompleteMultipartUpload',
      nest: () {
        builder.attribute('xmlns', 'http://s3.amazonaws.com/doc/2006-03-01/');
        for (final part in sortedParts) {
          builder.element(
            'Part',
            nest: part.toXml().children,
          );
        }
      },
    );

    return builder.buildDocument();
  }
}

class const S3CompleteMultipartUploadResult({
  required final String location,
  required final String bucket,
  required final String key,
  required final S3Etag eTag,
  final String? versionId,
}) {
  factory S3CompleteMultipartUploadResult.fromXml(
    XmlElement element, {
    String? versionId,
  }) {
    return S3CompleteMultipartUploadResult(
      location: element.str('Location'),
      bucket: element.str('Bucket'),
      key: element.str('Key'),
      eTag: S3Etag.parse(element.str('ETag')),
      versionId: versionId,
    );
  }

  factory S3CompleteMultipartUploadResult.fromXmlDocument(
    String xml, {
    String? versionId,
  }) {
    return S3CompleteMultipartUploadResult.fromXml(
      XmlDocument.parse(
        xml,
      ).findElements('CompleteMultipartUploadResult').first,
      versionId: versionId,
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element(
      'CompleteMultipartUploadResult',
      nest: () {
        builder.element('Location', nest: location);
        builder.element('Bucket', nest: bucket);
        builder.element('Key', nest: key);
        builder.element('ETag', nest: '"$eTag"');
      },
    );
    return builder.buildDocument();
  }
}

class const S3ObjectIdentifier({
  required final String key,
  final String? versionId,
}) {
  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element('Key', nest: key);
    if (versionId != null) {
      builder.element('VersionId', nest: versionId);
    }
    return builder.buildDocument();
  }
}

class const S3Delete({
  required final List<S3ObjectIdentifier> objects,
  final bool quiet = false,
}) {
  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element(
      'Delete',
      nest: () {
        if (quiet) builder.element('Quiet', nest: 'true');
        for (final o in objects) {
          builder.element('Object', nest: o.toXml().children);
        }
      },
    );
    return builder.buildDocument();
  }
}

class const S3DeletedObject({
  required final String key,
  final String? versionId,
  final bool deleteMarker = false,
  final String? deleteMarkerVersionId,
}) {
  factory S3DeletedObject.fromXml(XmlElement element) {
    return S3DeletedObject(
      key: element.str('Key'),
      versionId: element.strOrNull('VersionId'),
      deleteMarker: element.strOrNull('DeleteMarker') == 'true',
      deleteMarkerVersionId: element.strOrNull('DeleteMarkerVersionId'),
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element('Key', nest: key);
    if (versionId != null) {
      builder.element('VersionId', nest: versionId);
    }
    if (deleteMarker) {
      builder.element('DeleteMarker', nest: 'true');
    }
    if (deleteMarkerVersionId != null) {
      builder.element('DeleteMarkerVersionId', nest: deleteMarkerVersionId);
    }
    return builder.buildDocument();
  }
}

class const S3DeleteObjectsResult({
  final List<S3DeletedObject> deleted = const [],
  final List<S3Error> errors = const [],
}) {
  factory S3DeleteObjectsResult.fromXml(XmlElement element) {
    return S3DeleteObjectsResult(
      deleted: element
          .findElements('Deleted')
          .map(S3DeletedObject.fromXml)
          .toList(growable: false),
      errors: element
          .findElements('Error')
          .map(S3Error.fromXml)
          .toList(growable: false),
    );
  }

  factory S3DeleteObjectsResult.fromXmlDocument(String xml) {
    return S3DeleteObjectsResult.fromXml(
      XmlDocument.parse(xml).findElements('DeleteResult').first,
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element(
      'DeleteResult',
      nest: () {
        for (final d in deleted) {
          builder.element('Deleted', nest: d.toXml().children);
        }
        for (final e in errors) {
          builder.element('Error', nest: e.toXml().children);
        }
      },
    );
    return builder.buildDocument();
  }
}

class const S3Part({
  required final int partNumber,
  required final DateTime lastModified,
  required final S3Etag eTag,
  required final int size,
}) {
  factory S3Part.fromXml(XmlElement element) {
    return S3Part(
      partNumber: element.integer('PartNumber'),
      lastModified: element.dateTime('LastModified'),
      eTag: S3Etag.parse(element.str('ETag')),
      size: element.integer('Size'),
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element('PartNumber', nest: partNumber);
    builder.element(
      'LastModified',
      nest: lastModified.toUtc().toIso8601String(),
    );
    builder.element('ETag', nest: '"$eTag"');
    builder.element('Size', nest: size);
    return builder.buildDocument();
  }
}

class const S3ListPartsResult({
  required final String bucket,
  required final String key,
  required final String uploadId,
  required final int partNumberMarker,
  required final int maxParts,
  required final bool isTruncated,
  final int? nextPartNumberMarker,
  final List<S3Part> parts = const [],
  final S3Initiator? initiator,
  final S3Owner? owner,
  final String? storageClass,
}) {
  factory S3ListPartsResult.fromXml(XmlElement element) {
    final initiatorElement = element.getElement('Initiator');
    final ownerElement = element.getElement('Owner');
    return S3ListPartsResult(
      bucket: element.str('Bucket'),
      key: element.str('Key'),
      uploadId: element.str('UploadId'),
      partNumberMarker: element.integer('PartNumberMarker'),
      nextPartNumberMarker: element.integerOrNull('NextPartNumberMarker'),
      maxParts: element.integer('MaxParts'),
      isTruncated: element.boolean('IsTruncated'),
      parts: element
          .findElements('Part')
          .map(S3Part.fromXml)
          .toList(growable: false),
      initiator: initiatorElement != null
          ? S3Initiator.fromXml(initiatorElement)
          : null,
      owner: ownerElement != null ? S3Owner.fromXml(ownerElement) : null,
      storageClass: element.strOrNull('StorageClass'),
    );
  }

  factory S3ListPartsResult.fromXmlDocument(String xml) {
    return S3ListPartsResult.fromXml(
      XmlDocument.parse(xml).findElements('ListPartsResult').first,
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element(
      'ListPartsResult',
      nest: () {
        builder.element('Bucket', nest: bucket);
        builder.element('Key', nest: key);
        builder.element('UploadId', nest: uploadId);
        builder.element('PartNumberMarker', nest: partNumberMarker);
        if (nextPartNumberMarker != null) {
          builder.element('NextPartNumberMarker', nest: nextPartNumberMarker);
        }
        builder.element('MaxParts', nest: maxParts);
        builder.element('IsTruncated', nest: isTruncated.toString());
        for (final p in parts) {
          builder.element('Part', nest: p.toXml().children);
        }
        if (initiator case final initiator?) {
          builder.element('Initiator', nest: initiator.toXml().children);
        }
        if (owner case final owner?) {
          builder.element('Owner', nest: owner.toXml().children);
        }
        if (storageClass != null) {
          builder.element('StorageClass', nest: storageClass);
        }
      },
    );
    return builder.buildDocument();
  }
}

class const S3CopyPartResult({
  required final S3Etag eTag,
  required final DateTime lastModified,
}) {
  factory S3CopyPartResult.fromXml(XmlElement element) {
    return S3CopyPartResult(
      eTag: S3Etag.parse(element.str('ETag')),
      lastModified: element.dateTime('LastModified'),
    );
  }

  factory S3CopyPartResult.fromXmlDocument(String xml) {
    return S3CopyPartResult.fromXml(
      XmlDocument.parse(xml).findElements('CopyPartResult').first,
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element(
      'CopyPartResult',
      nest: () {
        builder.element('ETag', nest: '"$eTag"');
        builder.element(
          'LastModified',
          nest: lastModified.toUtc().toIso8601String(),
        );
      },
    );
    return builder.buildDocument();
  }
}

class const S3MultipartUpload({
  required final String key,
  required final String uploadId,
  final S3Initiator? initiator,
  final DateTime? initiated,
  final S3Owner? owner,
  final String? storageClass,
}) {
  factory S3MultipartUpload.fromXml(XmlElement element) {
    final initiatorElement = element.getElement('Initiator');
    final ownerElement = element.getElement('Owner');
    return S3MultipartUpload(
      key: element.str('Key'),
      uploadId: element.str('UploadId'),
      initiator: initiatorElement != null
          ? S3Initiator.fromXml(initiatorElement)
          : null,
      initiated: element.dateTimeOrNull('Initiated'),
      owner: ownerElement != null ? S3Owner.fromXml(ownerElement) : null,
      storageClass: element.strOrNull('StorageClass'),
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder()
      ..element('Key', nest: key)
      ..element('UploadId', nest: uploadId);
    if (initiator case final initiator?) {
      builder.element('Initiator', nest: initiator.toXml().children);
    }
    if (initiated case final initiated?) {
      builder.element('Initiated', nest: initiated.toUtc().toIso8601String());
    }
    if (owner case final owner?) {
      builder.element('Owner', nest: owner.toXml().children);
    }
    if (storageClass != null) {
      builder.element('StorageClass', nest: storageClass);
    }
    return builder.buildDocument();
  }
}

class const S3ListMultipartUploadsResult({
  required final String bucket,
  required final int maxUploads,
  required final bool isTruncated,
  final String? keyMarker,
  final String? uploadIdMarker,
  final String? nextKeyMarker,
  final String? nextUploadIdMarker,
  final String? prefix,
  final String? delimiter,
  final List<String> commonPrefixes = const [],
  final List<S3MultipartUpload> uploads = const [],
}) {
  factory S3ListMultipartUploadsResult.fromXml(XmlElement element) {
    return S3ListMultipartUploadsResult(
      bucket: element.str('Bucket'),
      keyMarker: element.strOrNull('KeyMarker'),
      uploadIdMarker: element.strOrNull('UploadIdMarker'),
      nextKeyMarker: element.strOrNull('NextKeyMarker'),
      nextUploadIdMarker: element.strOrNull('NextUploadIdMarker'),
      maxUploads: element.integer('MaxUploads'),
      isTruncated: element.boolean('IsTruncated'),
      prefix: element.strOrNull('Prefix'),
      delimiter: element.strOrNull('Delimiter'),
      commonPrefixes: element
          .findElements('CommonPrefixes')
          .map((e) => e.str('Prefix'))
          .toList(growable: false),
      uploads: element
          .findElements('Upload')
          .map(S3MultipartUpload.fromXml)
          .toList(growable: false),
    );
  }

  factory S3ListMultipartUploadsResult.fromXmlDocument(String xml) {
    return S3ListMultipartUploadsResult.fromXml(
      XmlDocument.parse(xml).findElements('ListMultipartUploadsResult').first,
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element(
      'ListMultipartUploadsResult',
      nest: () {
        builder.element('Bucket', nest: bucket);
        if (keyMarker != null) {
          builder.element('KeyMarker', nest: keyMarker);
        }
        if (uploadIdMarker != null) {
          builder.element('UploadIdMarker', nest: uploadIdMarker);
        }
        if (nextKeyMarker != null) {
          builder.element('NextKeyMarker', nest: nextKeyMarker);
        }
        if (nextUploadIdMarker != null) {
          builder.element('NextUploadIdMarker', nest: nextUploadIdMarker);
        }
        builder.element('MaxUploads', nest: maxUploads);
        builder.element('IsTruncated', nest: isTruncated.toString());
        if (prefix != null) {
          builder.element('Prefix', nest: prefix);
        }
        if (delimiter != null) {
          builder.element('Delimiter', nest: delimiter);
        }
        for (final cp in commonPrefixes) {
          builder.element(
            'CommonPrefixes',
            nest: () {
              builder.element('Prefix', nest: cp);
            },
          );
        }
        for (final u in uploads) {
          builder.element('Upload', nest: u.toXml().children);
        }
      },
    );
    return builder.buildDocument();
  }
}

class const S3ObjectVersion({
  required final String key,
  required final String versionId,
  required final bool isLatest,
  required final DateTime lastModified,
  required final S3Etag eTag,
  required final int size,
  required final String storageClass,
  final S3Owner? owner,
}) {
  factory S3ObjectVersion.fromXml(XmlElement element) {
    final ownerElement = element.getElement('Owner');
    return S3ObjectVersion(
      key: element.str('Key'),
      versionId: element.str('VersionId'),
      isLatest: element.boolean('IsLatest'),
      lastModified: element.dateTime('LastModified'),
      eTag: S3Etag.parse(element.str('ETag')),
      size: element.integer('Size'),
      storageClass: element.str('StorageClass'),
      owner: ownerElement != null ? S3Owner.fromXml(ownerElement) : null,
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder()
      ..element('Key', nest: key)
      ..element('VersionId', nest: versionId)
      ..element('IsLatest', nest: isLatest.toString())
      ..element(
        'LastModified',
        nest: lastModified.toUtc().toIso8601String(),
      )
      ..element('ETag', nest: '"$eTag"')
      ..element('Size', nest: size)
      ..element('StorageClass', nest: storageClass);
    if (owner case final owner?) {
      builder.element('Owner', nest: owner.toXml().children);
    }
    return builder.buildDocument();
  }
}

class const S3DeleteMarkerEntry({
  required final String key,
  required final String versionId,
  required final bool isLatest,
  required final DateTime lastModified,
  final S3Owner? owner,
}) {
  factory S3DeleteMarkerEntry.fromXml(XmlElement element) {
    final ownerElement = element.getElement('Owner');
    return S3DeleteMarkerEntry(
      key: element.str('Key'),
      versionId: element.str('VersionId'),
      isLatest: element.boolean('IsLatest'),
      lastModified: element.dateTime('LastModified'),
      owner: ownerElement != null ? S3Owner.fromXml(ownerElement) : null,
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder()
      ..element('Key', nest: key)
      ..element('VersionId', nest: versionId)
      ..element('IsLatest', nest: isLatest.toString())
      ..element('LastModified', nest: lastModified.toUtc().toIso8601String());
    if (owner case final owner?) {
      builder.element('Owner', nest: owner.toXml().children);
    }
    return builder.buildDocument();
  }
}

class const S3ListObjectVersionsResult({
  required final String name,
  required final int maxKeys,
  required final bool isTruncated,
  final String? prefix,
  final String? keyMarker,
  final String? versionIdMarker,
  final String? nextKeyMarker,
  final String? nextVersionIdMarker,
  final List<S3ObjectVersion> versions = const [],
  final List<S3DeleteMarkerEntry> deleteMarkers = const [],
  final List<String> commonPrefixes = const [],
  final String? delimiter,
  final String? encodingType,
}) {
  factory S3ListObjectVersionsResult.fromXml(XmlElement element) {
    return S3ListObjectVersionsResult(
      name: element.str('Name'),
      prefix: element.strOrNull('Prefix'),
      keyMarker: element.strOrNull('KeyMarker'),
      versionIdMarker: element.strOrNull('VersionIdMarker'),
      nextKeyMarker: element.strOrNull('NextKeyMarker'),
      nextVersionIdMarker: element.strOrNull('NextVersionIdMarker'),
      maxKeys: element.integer('MaxKeys'),
      isTruncated: element.boolean('IsTruncated'),
      versions: element
          .findElements('Version')
          .map(S3ObjectVersion.fromXml)
          .toList(growable: false),
      deleteMarkers: element
          .findElements('DeleteMarker')
          .map(S3DeleteMarkerEntry.fromXml)
          .toList(growable: false),
      commonPrefixes: element
          .findElements('CommonPrefixes')
          .map((e) => e.str('Prefix'))
          .toList(growable: false),
      delimiter: element.strOrNull('Delimiter'),
      encodingType: element.strOrNull('EncodingType'),
    );
  }

  factory S3ListObjectVersionsResult.fromXmlDocument(String xml) {
    return S3ListObjectVersionsResult.fromXml(
      XmlDocument.parse(xml).findElements('ListVersionsResult').first,
    );
  }

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element(
      'ListVersionsResult',
      nest: () {
        builder.element('Name', nest: name);
        if (prefix != null) builder.element('Prefix', nest: prefix);
        if (keyMarker != null) builder.element('KeyMarker', nest: keyMarker);
        if (versionIdMarker != null) {
          builder.element('VersionIdMarker', nest: versionIdMarker);
        }
        builder.element('MaxKeys', nest: maxKeys);
        builder.element('IsTruncated', nest: isTruncated.toString());
        for (final v in versions) {
          builder.element('Version', nest: v.toXml().children);
        }
        for (final dm in deleteMarkers) {
          builder.element('DeleteMarker', nest: dm.toXml().children);
        }
        for (final cp in commonPrefixes) {
          builder.element(
            'CommonPrefixes',
            nest: () {
              builder.element('Prefix', nest: cp);
            },
          );
        }
        if (nextKeyMarker != null) {
          builder.element('NextKeyMarker', nest: nextKeyMarker);
        }
        if (nextVersionIdMarker != null) {
          builder.element('NextVersionIdMarker', nest: nextVersionIdMarker);
        }
        if (delimiter != null) {
          builder.element('Delimiter', nest: delimiter);
        }
        if (encodingType != null) {
          builder.element('EncodingType', nest: encodingType);
        }
      },
    );
    return builder.buildDocument();
  }
}

extension on XmlElement {
  String str(String name) => getElement(name)!.innerText;
  String? strOrNull(String name) => getElement(name)?.innerText;
  int integer(String name) => int.parse(str(name));
  int? integerOrNull(String name) => int.tryParse(strOrNull(name) ?? '');
  bool boolean(String name) => str(name).toLowerCase() == 'true';
  DateTime dateTime(String name) => DateTime.parse(str(name));
  DateTime? dateTimeOrNull(String name) {
    final value = strOrNull(name);
    return value != null ? DateTime.parse(value) : null;
  }
}

enum const S3ObjectAcl(final String headerValue) {
  private('private'),
  publicRead('public-read'),
  publicReadWrite('public-read-write'),
  authenticatedRead('authenticated-read');
}

extension type const S3Metadata(Map<String, String> _map)
    implements Map<String, String> {
  factory S3Metadata.fromHeaders(Map<String, String> headers) {
    const prefix = 'x-amz-meta-';

    final metadata = Map.fromEntries(
      headers.entries
          .where((e) => e.key.startsWith(prefix))
          .map((e) => MapEntry(e.key.substring(prefix.length), e.value)),
    );

    return S3Metadata(metadata);
  }
}
