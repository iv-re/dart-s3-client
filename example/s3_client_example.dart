import 'dart:convert';
import 'dart:typed_data';

import 'package:s3_client/s3_client.dart';
import 'package:sl/sl.dart';

void main() async {
  final logger = Logger(
    handler: LogTextHandler(level: .debug, theme: .ansi),
  );

  // Instantiating S3Client
  final s3 = S3Client(
    baseEndpoint: .parse('http://127.0.0.1:8333'),
    credentials: .static(
      accessKeyId: 'CI9TC85TBPPC3SSBETVM',
      secretAccessKey: 'StSaJAkediwifV40UtaFqoCr4XywVcGp5y8dyY0p',
    ),
    usePathStyle: true,
    logger: logger
        .withAttrs(const [.string('component', 's3')])
        .withGroup('s3'),
  );

  // final s3 = S3Client.aws(
  //   region: 'us-west-2',
  //   credentials: S3CredentialsProvider.static(
  //     accessKeyId: 'AWS_ACCESS_KEY_ID',
  //     secretAccessKey: 'AWS_SECRET_ACCESS_KEY',
  //   ),
  //   logger: logger,
  // );

  // final s3 = S3Client.r2(
  //   accountId: 'CLOUDFLARE_ACCOUNT_ID',
  //   credentials: S3CredentialsProvider.static(
  //     accessKeyId: 'R2_ACCESS_KEY_ID',
  //     secretAccessKey: 'R2_SECRET_ACCESS_KEY',
  //   ),
  //   logger: logger,
  // );

  const bucket = 'my-bucket';
  const key = 'example-object.txt';
  const copyKey = 'example-object-copy.txt';

  try {
    // Put Object
    logger.info('Uploading object...');
    final content = utf8.encode('Hello, S3 Client from Dart!');
    final putResult = await s3.putObject(
      bucket: bucket,
      key: key,
      body: Stream.value(Uint8List.fromList(content)),
      contentLength: content.length,
      contentType: 'text/plain',
      metadata: {'author': 'pusk'},
    );
    logger.info(
      'Uploaded! ETag: ${putResult.eTag}, VersionId: ${putResult.versionId}',
    );

    // Head Object
    logger.info('Retrieving object metadata (HEAD)...');
    final headResult = await s3.headObject(bucket: bucket, key: key);
    logger.info(
      'Metadata - Length: ${headResult.contentLength}, '
      'ETag: ${headResult.eTag}, '
      'Author: ${headResult.metadata['author']}',
    );

    // Get Object
    logger.info('Downloading object...');
    final getResult = await s3.getObject(bucket: bucket, key: key);
    final dataString = await getResult.bytesToString();
    logger.info('Downloaded content: "$dataString"');

    // Presigned URL for PUT
    logger.info('Generating presigned PUT URL...');
    final presignedPutUri = await s3.presignPutObject(
      bucket: bucket,
      key: key,
      expires: const Duration(minutes: 10),
    );
    logger.info('Presigned PUT URL: $presignedPutUri');

    // Presigned URL for GET
    logger.info('Generating presigned GET URL...');
    final presignedGetUri = await s3.presignGetObject(
      bucket: bucket,
      key: key,
      expires: const Duration(minutes: 10),
    );
    logger.info('Presigned GET URL: $presignedGetUri');

    // Copy Object
    logger.info('Copying object to $copyKey...');
    final copyResult = await s3.copyObject(
      bucket: bucket,
      key: copyKey,
      copySource: '$bucket/$key',
      metadataDirective: .replace,
      metadata: {'copied': 'true'},
    );
    logger.info('Copied object. ETag: ${copyResult.eTag}');

    // List Objects V2
    logger.info('Listing objects...');
    await for (final page in s3.listObjectsV2(bucket: bucket)) {
      logger.info('Bucket Page: ${page.name}');
      for (final obj in page.contents) {
        logger.info(' - ${obj.key} (${obj.size} bytes)');
      }
    }

    // List Object Versions
    logger.info('Listing object versions...');
    await for (final page in s3.listObjectVersions(bucket: bucket)) {
      for (final version in page.versions) {
        logger.info(' - Version: ${version.key} (ID: ${version.versionId})');
      }
    }

    // Create Multipart Upload
    logger.info('Initiating multipart upload...');
    const mpKey = 'large-file.bin';
    final uploadId = await s3.createMultipartUpload(
      bucket: bucket,
      key: mpKey,
      contentType: 'application/octet-stream',
    );
    logger.info('Initiated. Upload ID: $uploadId');

    // List Multipart Uploads
    logger.info('Listing active multipart uploads...');
    await for (final page in s3.listMultipartUploads(bucket: bucket)) {
      for (final upload in page.uploads) {
        logger.info(
          ' - Pending Upload: ${upload.key} (ID: ${upload.uploadId})',
        );
      }
    }

    // Upload Part
    logger.info('Uploading Part 1 (5MB of zeroes)...');
    // Note: S3 requires parts (except the last one) to be at least 5MB.
    final part1Data = Uint8List(5 * 1024 * 1024);
    final etag1 = await s3.uploadPart(
      bucket: bucket,
      key: mpKey,
      uploadId: uploadId,
      partNumber: 1,
      body: Stream.value(part1Data),
      contentLength: part1Data.length,
    );
    logger.info('Part 1 uploaded. ETag: $etag1');

    // Upload Part Copy
    logger.info('Uploading Part 2 by copying from another object...');
    final copyPartResult = await s3.uploadPartCopy(
      bucket: bucket,
      key: mpKey,
      uploadId: uploadId,
      partNumber: 2,
      copySource: '$bucket/$key',
    );
    logger.info('Part 2 copied. ETag: ${copyPartResult.eTag}');

    // List Parts
    logger.info('Listing uploaded parts for $mpKey...');
    final listPartsStream = s3.listParts(
      bucket: bucket,
      key: mpKey,
      uploadId: uploadId,
    );
    await for (final page in listPartsStream) {
      for (final part in page.parts) {
        logger.info(
          ' - Part ${part.partNumber}: size=${part.size}, ETag=${part.eTag}',
        );
      }
    }

    // Complete Multipart Upload
    logger.info('Completing multipart upload...');
    final completeResult = await s3.completeMultipartUpload(
      bucket: bucket,
      key: mpKey,
      uploadId: uploadId,
      multipartUpload: S3CompleteMultipartUpload(
        parts: [
          S3CompletedPart(partNumber: 1, eTag: etag1),
          S3CompletedPart(partNumber: 2, eTag: copyPartResult.eTag),
        ],
      ),
    );
    logger.info('Completed! Location: ${completeResult.location}');

    // Abort Multipart Upload Example
    logger.info('Demonstrating abort multipart upload...');
    final abortUploadId = await s3.createMultipartUpload(
      bucket: bucket,
      key: 'temp-multipart.bin',
    );
    await s3.abortMultipartUpload(
      bucket: bucket,
      key: 'temp-multipart.bin',
      uploadId: abortUploadId,
    );
    logger.info('Multipart upload successfully aborted.');

    // Delete Single Object
    logger.info('Deleting copied object...');
    await s3.deleteObject(bucket: bucket, key: copyKey);
    logger.info('Deleted $copyKey');

    // Delete Objects (Bulk)
    logger.info('Performing bulk delete of remaining objects...');
    final deleteResult = await s3.deleteObjects(
      bucket: bucket,
      objects: const [
        S3ObjectIdentifier(key: key),
        S3ObjectIdentifier(key: mpKey),
      ],
    );
    for (final deleted in deleteResult.deleted) {
      logger.info(' - Deleted: ${deleted.key}');
    }
    for (final error in deleteResult.errors) {
      logger.info(' - Error deleting ${error.key}: ${error.message}');
    }
  } catch (error, stackTrace) {
    logger.error('An error occurred during S3 operation: $error');
    logger.error(stackTrace.toString());
  }
}
