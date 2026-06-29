import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:s3_client/src/credentials.dart';
import 'package:s3_client/src/request.dart';
import 'package:s3_client/src/sign/canonical_request.dart';
import 'package:s3_client/src/sign/date_time.dart';

typedef _SigContext = ({
  String dateBasic,
  String dateOnly,
  String credentialScope,
  String secretAccessKey,
});

@internal
class S3Signer {
  S3Signer({
    required this.credentialsProvider,
    required this.region,
  });

  final S3CredentialsProvider credentialsProvider;
  final String region;

  static const _algorithm = 'AWS4-HMAC-SHA256';
  static const _service = 's3';
  static const _requestType = 'aws4_request';
  static const _unsignedPayload = 'UNSIGNED-PAYLOAD';
  static const _emptyPayloadHash =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

  FutureOr<void> sign(S3BaseRequest req) async {
    final credentials = await credentialsProvider.retrieve();
    if (credentials.isAnonymous) return;

    final s3Date = S3DateTime.now();
    final dateBasic = s3Date.toIso8601Basic();
    final dateOnly = s3Date.toIso8601BasicDate();

    final credentialScope = _buildCredentialScope(dateOnly);
    final payloadHash = _getPayloadHash(req);

    req.headers[S3HttpHeaders.date] = dateBasic;
    req.headers[S3HttpHeaders.contentSha256] = payloadHash;
    req.headers[S3HttpHeaders.host] = req.url.authority;

    if (credentials.sessionToken != null) {
      req.headers[S3HttpHeaders.securityToken] = credentials.sessionToken!;
    }

    final canonicalRequest = CanonicalRequest(
      method: req.method,
      url: req.url,
      queryParameters: req.url.queryParametersAll,
      headers: req.headers,
      payloadHash: payloadHash,
    );

    final context = (
      dateBasic: dateBasic,
      dateOnly: dateOnly,
      credentialScope: credentialScope,
      secretAccessKey: credentials.secretAccessKey!,
    );

    final signatureHex = _computeSignature(canonicalRequest, context);

    req.headers[S3HttpHeaders.authorization] =
        '$_algorithm '
        'Credential=${credentials.accessKeyId}/$credentialScope, '
        'SignedHeaders=${canonicalRequest.signedHeaders}, '
        'Signature=$signatureHex';
  }

  Future<Uri> presign(
    String method,
    Uri url, {
    Duration expires = const Duration(minutes: 15),
  }) async {
    final credentials = await credentialsProvider.retrieve();
    if (credentials.isAnonymous) return url;

    final s3Date = S3DateTime.now();
    final dateBasic = s3Date.toIso8601Basic();
    final dateOnly = s3Date.toIso8601BasicDate();
    final credentialScope = _buildCredentialScope(dateOnly);

    final queryParams = Map<String, List<String>>.from(url.queryParametersAll);
    queryParams[S3QueryParams.algorithm] = [_algorithm];
    queryParams[S3QueryParams.credential] = [
      '${credentials.accessKeyId}/$credentialScope',
    ];
    queryParams[S3QueryParams.date] = [dateBasic];
    queryParams[S3QueryParams.expires] = [expires.inSeconds.toString()];
    queryParams[S3QueryParams.signedHeaders] = [S3HttpHeaders.host];

    if (credentials.sessionToken case final sessionToken?) {
      queryParams[S3QueryParams.securityToken] = [sessionToken];
    }

    final canonicalRequest = CanonicalRequest(
      method: method,
      url: url,
      queryParameters: queryParams,
      headers: {S3HttpHeaders.host: url.authority},
      payloadHash: _unsignedPayload,
    );

    final context = (
      dateBasic: dateBasic,
      dateOnly: dateOnly,
      credentialScope: credentialScope,
      secretAccessKey: credentials.secretAccessKey!,
    );

    final signatureHex = _computeSignature(canonicalRequest, context);

    final finalQueryParams = queryParams.map((k, v) => MapEntry(k, v.first));
    finalQueryParams[S3QueryParams.signature] = signatureHex;

    return url.replace(queryParameters: finalQueryParams);
  }

  String _buildCredentialScope(String dateOnly) {
    return '$dateOnly/$region/$_service/$_requestType';
  }

  String _computeSignature(
    CanonicalRequest canonicalRequest,
    _SigContext context,
  ) {
    final stringToSign = [
      _algorithm,
      context.dateBasic,
      context.credentialScope,
      canonicalRequest.hash,
    ].join('\n');

    final signingKey = _getSigningKey(
      context.secretAccessKey,
      context.dateOnly,
    );

    return _hmacSha256(signingKey, stringToSign).toString();
  }

  String _getPayloadHash(S3BaseRequest req) {
    for (final entry in req.headers.entries) {
      if (entry.key.toLowerCase() == S3HttpHeaders.contentSha256) {
        return entry.value;
      }
    }

    if (req is S3Request) {
      final body = req.bodyBytes;
      return body.isEmpty ? _emptyPayloadHash : sha256.convert(body).toString();
    }

    return _unsignedPayload;
  }

  List<int> _getSigningKey(String secretKey, String date) {
    final kDate = _hmacSha256(utf8.encode('AWS4$secretKey'), date).bytes;
    final kRegion = _hmacSha256(kDate, region).bytes;
    final kService = _hmacSha256(kRegion, _service).bytes;
    return _hmacSha256(kService, _requestType).bytes;
  }

  Digest _hmacSha256(List<int> key, String data) {
    return Hmac(sha256, key).convert(utf8.encode(data));
  }
}
