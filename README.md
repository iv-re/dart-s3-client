# s3_client

An S3-compatible storage client.

## Setup

### AWS S3

```dart
import 'package:s3_client/s3_client.dart';

final s3 = S3Client.aws(
  region: 'us-east-1',
  credentials: .static(
    accessKeyId: 'YOUR_ACCESS_KEY',
    secretAccessKey: 'YOUR_SECRET_KEY',
  ),
);
```

### Cloudflare R2

```dart
import 'package:s3_client/s3_client.dart';

final s3 = S3Client.r2(
  accountId: 'YOUR_ACCOUNT_ID',
  credentials: .static(
    accessKeyId: 'YOUR_ACCESS_KEY',
    secretAccessKey: 'YOUR_SECRET_KEY',
  ),
);
```

### Generic S3-Compatible Storage

```dart
import 'package:s3_client/s3_client.dart';

final s3 = S3Client(
  baseEndpoint: .parse('https://s3.example.com'),
  region: 'us-east-1',
  credentials: .static(
    accessKeyId: 'YOUR_ACCESS_KEY',
    secretAccessKey: 'YOUR_SECRET_KEY',
  ),
  usePathStyle: true, // Set to true if the provider requires path-style addressing
);
```

### Credentials Providers

- **Static**: `S3CredentialsProvider.static(accessKeyId: ..., secretAccessKey: ...)`
- **Anonymous**: `S3CredentialsProvider.anonymous()`
- **Cached**: `S3CredentialsProvider.cached(provider)` - wraps and caches temporary credentials.

#### Custom Provider

To fetch credentials dynamically (e.g. from an STS or your backend), implement `S3CredentialsProvider`:

```dart
class MyCustomProvider implements S3CredentialsProvider {
  @override
  Future<S3Credentials> retrieve() async {
    return S3Credentials(
      accessKeyId: 'ACCESS_KEY',
      secretAccessKey: 'SECRET_KEY',
      sessionToken: 'SESSION_TOKEN', // optional
      expires: DateTime.now().add(Duration(hours: 1)), // optional
    );
  }
}
```

## Basic Operations

### Uploading an Object

```dart
final result = await s3.putObject(
  bucket: 'my-bucket',
  key: 'path/to/file.txt',
  body: Stream.value(Uint8List.fromList(utf8.encode('hello world'))),
  contentLength: 11,
  contentType: 'text/plain',
);
print(result.eTag);
print(result.versionId);
```

### Downloading an Object

```dart
final objectStream = await s3.getObject(
  bucket: 'my-bucket',
  key: 'path/to/file.txt',
);

final content = await objectStream.bytesToString();
print(content); // hello world
```

### Listing Objects

```dart
await for (final page in s3.listObjectsV2(bucket: 'my-bucket', prefix: 'photos/')) {
  for (final object in page.contents) {
    print('Found object: ${object.key} (Size: ${object.size})');
  }
}
```

### Deleting Objects

```dart
// Single object
await s3.deleteObject(bucket: 'my-bucket', key: 'path/to/file.txt');

// Bulk delete (automatically chunked into batches of 1000)
await s3.deleteObjects(
  bucket: 'my-bucket',
  objects: [
    S3ObjectIdentifier(key: 'file1.txt'),
    S3ObjectIdentifier(key: 'file2.txt'),
  ],
);
```

## Multipart Upload

Useful for uploading large files in chunks:

```dart
// 1. Initiate upload
final uploadId = await s3.createMultipartUpload(
  bucket: 'my-bucket',
  key: 'large-file.bin',
);

final parts = <S3CompletedPart>[];

try {
  // 2. Upload parts (each part must be >= 5MB except the last one)
  final etag = await s3.uploadPart(
    bucket: 'my-bucket',
    key: 'large-file.bin',
    uploadId: uploadId,
    partNumber: 1,
    body: Stream.value(partData),
    contentLength: partData.length,
  );
  parts.add(S3CompletedPart(partNumber: 1, eTag: etag));

  // 3. Complete upload
  await s3.completeMultipartUpload(
    bucket: 'my-bucket',
    key: 'large-file.bin',
    uploadId: uploadId,
    multipartUpload: S3CompleteMultipartUpload(parts: parts),
  );
} catch (e) {
  // Abort on failure to clean up S3 storage
  await s3.abortMultipartUpload(
    bucket: 'my-bucket',
    key: 'large-file.bin',
    uploadId: uploadId,
  );
}
```

## Presigned URLs

Generate temporary, pre-authorized URLs for direct upload/download:

```dart
// Presigned GET (valid for 15 minutes)
final downloadUri = await s3.presignGetObject(
  bucket: 'my-bucket',
  key: 'file.txt',
  expires: Duration(minutes: 15),
);

// Presigned PUT
final uploadUri = await s3.presignPutObject(
  bucket: 'my-bucket',
  key: 'file.txt',
  expires: Duration(minutes: 15),
);
```

## Context & Cancellation

Pass `package:ctx` contexts to enforce deadlines, timeouts, or cancellation:

```dart
import 'package:ctx/ctx.dart';

final (ctx, cancel) = Context.empty().withTimeout(Duration(seconds: 10));

try {
  final stream = await s3.getObject(
    bucket: 'my-bucket',
    key: 'large-file.bin',
    ctx: ctx,
  );
} finally {
  cancel();
}
```

## Error Handling

Errors from the S3 API are mapped to specific subclasses of `S3Exception`:

```dart
try {
  await s3.getObject(bucket: 'my-bucket', key: 'non-existent.txt');
} on S3NoSuchKeyException {
  print('File does not exist.');
} on S3AccessDeniedException {
  print('Access denied.');
} on S3Exception catch (e) {
  print('S3 error: ${e.code} - ${e.message}');
}
```