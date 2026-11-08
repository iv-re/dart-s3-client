## 1.1.0

- Add `contentDisposition`, `contentEncoding`, `contentLanguage`,
  `cacheControl`, `expires`, `ifMatch` and `ifNoneMatch` parameters to
  `putObject`.
- Add `contentDisposition`, `contentEncoding`, `contentLanguage`,
  `cacheControl` and `expires` parameters to `createMultipartUpload` and
  `copyObject`.
- Add `ifMatch` and `ifNoneMatch` parameters to `completeMultipartUpload`.
- Add `copySourceVersionId` parameter to `copyObject` and `uploadPartCopy`.
- Add `S3ConditionalRequestConflictException`.
- Fix `copyObject` ignoring `tagging` by sending `x-amz-tagging-directive`.
- Throw `S3Exception` when `copyObject`, `uploadPartCopy` or
  `completeMultipartUpload` receive an error inside a `200 OK` response.
- Fix `putObject` and `uploadPart` hanging when the connection fails.
- Reject object keys with `.` or `..` path segments with an `ArgumentError`
  instead of silently addressing a different object.
- Percent-encode `+` in object keys.
- Fix `S3CachedCredentialsProvider` caching a synchronous provider failure.
- Add `S3NotModifiedException` and map 304, 403 and 412 responses without a
  body to typed exceptions.
- Return `null` from `S3HeadObjectResult.expires` for an invalid `Expires`.
- Tolerate missing `StorageClass`, `PartNumberMarker` and error `Message`
  elements in S3 responses.
- Require Dart SDK `^3.13.0`.
- Allow `sl` 2.x.

## 1.0.0

- Support `Context.current` when explicit `ctx` parameter is omitted.

## 0.0.1

- Initial version.
