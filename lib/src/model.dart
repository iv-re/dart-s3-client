import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http_parser/http_parser.dart' as http;
import 'package:s3_client/src/request.dart';
import 'package:xml/xml.dart';

class S3ObjectStream extends StreamView<Uint8List> {
  S3ObjectStream({
    required Stream<List<int>> body,
    required this.contentLength,
    required this.contentType,
    this.eTag,
    this.lastModified,
    this.versionId,
    this.deleteMarker,
    this.metadata = const {},
    this.storageClass,
    this.acceptRanges,
  }) : super(body.cast<Uint8List>());

  final int? contentLength;
  final String? contentType;
  final S3Etag? eTag;
  final DateTime? lastModified;
  final String? versionId;
  final bool? deleteMarker;
  final Map<String, String> metadata;
  final String? storageClass;
  final String? acceptRanges;

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

class S3Owner {
  const S3Owner({
    required this.id,
    this.displayName,
  });

  factory S3Owner.fromXml(XmlElement element) {
    return S3Owner(
      id: element.str('ID'),
      displayName: element.strOrNull('DisplayName'),
    );
  }

  final String id;
  final String? displayName;

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element('ID', nest: id);
    if (displayName != null) {
      builder.element('DisplayName', nest: displayName);
    }
    return builder.buildDocument();
  }
}

class S3Initiator {
  const S3Initiator({
    required this.id,
    this.displayName,
  });

  factory S3Initiator.fromXml(XmlElement element) {
    return S3Initiator(
      id: element.str('ID'),
      displayName: element.strOrNull('DisplayName'),
    );
  }

  final String id;
  final String? displayName;

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element('ID', nest: id);
    if (displayName != null) {
      builder.element('DisplayName', nest: displayName);
    }
    return builder.buildDocument();
  }
}

class S3Object {
  const S3Object({
    required this.key,
    required this.eTag,
    required this.size,
    required this.storageClass,
    required this.lastModified,
    this.owner,
  });

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

  final String key;
  final S3Etag eTag;
  final int size;
  final String storageClass;
  final DateTime lastModified;
  final S3Owner? owner;

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

class S3ListObjectsResult {
  const S3ListObjectsResult({
    required this.name,
    required this.prefix,
    required this.maxKeys,
    required this.isTruncated,
    required this.keyCount,
    required this.contents,
    this.commonPrefixes = const [],
    this.nextContinuationToken,
    this.delimiter,
    this.encodingType,
    this.continuationToken,
    this.startAfter,
  });

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

  final String name;
  final String prefix;
  final int maxKeys;
  final bool isTruncated;
  final int keyCount;
  final List<S3Object> contents;
  final List<String> commonPrefixes;
  final String? nextContinuationToken;
  final String? delimiter;
  final String? encodingType;
  final String? continuationToken;
  final String? startAfter;

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

class S3Error {
  const S3Error({
    required this.code,
    required this.message,
    this.key,
    this.versionId,
    this.requestId,
    this.hostId,
  });

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

  final String code;
  final String message;
  final String? key;
  final String? versionId;
  final String? requestId;
  final String? hostId;

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

class S3HeadObjectResult {
  const S3HeadObjectResult({
    required this.contentLength,
    required this.contentType,
    required this.eTag,
    required this.lastModified,
    this.metadata = const {},
    this.versionId,
    this.deleteMarker,
    this.storageClass,
    this.restore,
    this.cacheControl,
    this.contentDisposition,
    this.contentEncoding,
    this.contentLanguage,
    this.expires,
    this.acceptRanges,
  });

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

  final int? contentLength;
  final String? contentType;
  final S3Etag? eTag;
  final DateTime? lastModified;
  final Map<String, String> metadata;
  final String? versionId;
  final bool? deleteMarker;
  final String? storageClass;
  final String? restore;
  final String? cacheControl;
  final String? contentDisposition;
  final String? contentEncoding;
  final String? contentLanguage;
  final DateTime? expires;
  final String? acceptRanges;
}

enum S3MetadataDirective { copy, replace }

class S3PutObjectResult {
  const S3PutObjectResult({
    required this.eTag,
    this.versionId,
  });

  final S3Etag eTag;
  final String? versionId;
}

class S3CopyObjectResult {
  const S3CopyObjectResult({
    required this.eTag,
    required this.lastModified,
    this.versionId,
    this.copySourceVersionId,
  });

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

  final S3Etag eTag;
  final DateTime lastModified;
  final String? versionId;
  final String? copySourceVersionId;

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

extension type S3UploadId(String value) implements String {
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

class S3CompletedPart {
  const S3CompletedPart({
    required this.partNumber,
    required this.eTag,
  });

  final int partNumber;
  final S3Etag eTag;

  XmlNode toXml() {
    final builder = XmlBuilder()
      ..element('PartNumber', nest: partNumber)
      ..element('ETag', nest: '"$eTag"');
    return builder.buildDocument();
  }
}

class S3CompleteMultipartUpload {
  const S3CompleteMultipartUpload({
    required this.parts,
  });

  final List<S3CompletedPart> parts;

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

class S3CompleteMultipartUploadResult {
  const S3CompleteMultipartUploadResult({
    required this.location,
    required this.bucket,
    required this.key,
    required this.eTag,
    this.versionId,
  });

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

  final String location;
  final String bucket;
  final String key;
  final S3Etag eTag;
  final String? versionId;

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

class S3ObjectIdentifier {
  const S3ObjectIdentifier({
    required this.key,
    this.versionId,
  });

  final String key;
  final String? versionId;

  XmlNode toXml() {
    final builder = XmlBuilder();
    builder.element('Key', nest: key);
    if (versionId != null) {
      builder.element('VersionId', nest: versionId);
    }
    return builder.buildDocument();
  }
}

class S3Delete {
  const S3Delete({
    required this.objects,
    this.quiet = false,
  });

  final List<S3ObjectIdentifier> objects;
  final bool quiet;

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

class S3DeletedObject {
  const S3DeletedObject({
    required this.key,
    this.versionId,
    this.deleteMarker = false,
    this.deleteMarkerVersionId,
  });

  factory S3DeletedObject.fromXml(XmlElement element) {
    return S3DeletedObject(
      key: element.str('Key'),
      versionId: element.strOrNull('VersionId'),
      deleteMarker: element.strOrNull('DeleteMarker') == 'true',
      deleteMarkerVersionId: element.strOrNull('DeleteMarkerVersionId'),
    );
  }

  final String key;
  final String? versionId;
  final bool deleteMarker;
  final String? deleteMarkerVersionId;

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

class S3DeleteObjectsResult {
  const S3DeleteObjectsResult({
    this.deleted = const [],
    this.errors = const [],
  });

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

  final List<S3DeletedObject> deleted;
  final List<S3Error> errors;

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

class S3Part {
  const S3Part({
    required this.partNumber,
    required this.lastModified,
    required this.eTag,
    required this.size,
  });

  factory S3Part.fromXml(XmlElement element) {
    return S3Part(
      partNumber: element.integer('PartNumber'),
      lastModified: element.dateTime('LastModified'),
      eTag: S3Etag.parse(element.str('ETag')),
      size: element.integer('Size'),
    );
  }

  final int partNumber;
  final DateTime lastModified;
  final S3Etag eTag;
  final int size;

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

class S3ListPartsResult {
  const S3ListPartsResult({
    required this.bucket,
    required this.key,
    required this.uploadId,
    required this.partNumberMarker,
    required this.maxParts,
    required this.isTruncated,
    this.nextPartNumberMarker,
    this.parts = const [],
    this.initiator,
    this.owner,
    this.storageClass,
  });

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

  final String bucket;
  final String key;
  final String uploadId;
  final int partNumberMarker;
  final int? nextPartNumberMarker;
  final int maxParts;
  final bool isTruncated;
  final List<S3Part> parts;
  final S3Initiator? initiator;
  final S3Owner? owner;
  final String? storageClass;

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

class S3CopyPartResult {
  const S3CopyPartResult({
    required this.eTag,
    required this.lastModified,
  });

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

  final S3Etag eTag;
  final DateTime lastModified;

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

class S3MultipartUpload {
  const S3MultipartUpload({
    required this.key,
    required this.uploadId,
    this.initiator,
    this.initiated,
    this.owner,
    this.storageClass,
  });

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

  final String key;
  final String uploadId;
  final S3Initiator? initiator;
  final DateTime? initiated;
  final S3Owner? owner;
  final String? storageClass;

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

class S3ListMultipartUploadsResult {
  const S3ListMultipartUploadsResult({
    required this.bucket,
    required this.maxUploads,
    required this.isTruncated,
    this.keyMarker,
    this.uploadIdMarker,
    this.nextKeyMarker,
    this.nextUploadIdMarker,
    this.prefix,
    this.delimiter,
    this.commonPrefixes = const [],
    this.uploads = const [],
  });

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

  final String bucket;
  final String? keyMarker;
  final String? uploadIdMarker;
  final String? nextKeyMarker;
  final String? nextUploadIdMarker;
  final int maxUploads;
  final bool isTruncated;
  final String? prefix;
  final String? delimiter;
  final List<String> commonPrefixes;
  final List<S3MultipartUpload> uploads;

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

class S3ObjectVersion {
  const S3ObjectVersion({
    required this.key,
    required this.versionId,
    required this.isLatest,
    required this.lastModified,
    required this.eTag,
    required this.size,
    required this.storageClass,
    this.owner,
  });

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

  final String key;
  final String versionId;
  final bool isLatest;
  final DateTime lastModified;
  final S3Etag eTag;
  final int size;
  final String storageClass;
  final S3Owner? owner;

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

class S3DeleteMarkerEntry {
  const S3DeleteMarkerEntry({
    required this.key,
    required this.versionId,
    required this.isLatest,
    required this.lastModified,
    this.owner,
  });

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

  final String key;
  final String versionId;
  final bool isLatest;
  final DateTime lastModified;
  final S3Owner? owner;

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

class S3ListObjectVersionsResult {
  const S3ListObjectVersionsResult({
    required this.name,
    required this.maxKeys,
    required this.isTruncated,
    this.prefix,
    this.keyMarker,
    this.versionIdMarker,
    this.nextKeyMarker,
    this.nextVersionIdMarker,
    this.versions = const [],
    this.deleteMarkers = const [],
    this.commonPrefixes = const [],
    this.delimiter,
    this.encodingType,
  });

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

  final String name;
  final String? prefix;
  final String? keyMarker;
  final String? versionIdMarker;
  final String? nextKeyMarker;
  final String? nextVersionIdMarker;
  final int maxKeys;
  final bool isTruncated;
  final List<S3ObjectVersion> versions;
  final List<S3DeleteMarkerEntry> deleteMarkers;
  final List<String> commonPrefixes;
  final String? delimiter;
  final String? encodingType;

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

enum S3ObjectAcl {
  private('private'),
  publicRead('public-read'),
  publicReadWrite('public-read-write'),
  authenticatedRead('authenticated-read');

  const S3ObjectAcl(this.headerValue);

  final String headerValue;
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
