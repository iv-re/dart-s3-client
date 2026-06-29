import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:s3_client/src/request.dart';

@internal
class CanonicalRequest {
  factory CanonicalRequest({
    required String method,
    required Uri url,
    required Map<String, List<String>> queryParameters,
    required Map<String, String> headers,
    required String payloadHash,
  }) {
    final (canonicalHeaders, signedHeaders) = _canonicalizeHeaders(headers);

    return CanonicalRequest._(
      method: method,
      url: url,
      queryParameters: queryParameters,
      canonicalHeaders: canonicalHeaders,
      signedHeaders: signedHeaders,
      payloadHash: payloadHash,
    );
  }

  CanonicalRequest._({
    required this.method,
    required this.url,
    required this.queryParameters,
    required this.canonicalHeaders,
    required this.signedHeaders,
    required this.payloadHash,
  });

  final String method;
  final Uri url;
  final Map<String, List<String>> queryParameters;
  final String canonicalHeaders;
  final String signedHeaders;
  final String payloadHash;

  static final RegExp _whitespace = RegExp(r'\s+');
  static const Set<String> _ignoredHeaders = {S3HttpHeaders.userAgent};

  static (String, String) _canonicalizeHeaders(Map<String, String> headers) {
    final canonicalHeadersMap = SplayTreeMap<String, String>();

    for (final entry in headers.entries) {
      final lowercaseKey = entry.key.toLowerCase();
      if (!_ignoredHeaders.contains(lowercaseKey)) {
        canonicalHeadersMap[lowercaseKey] = entry.value.trim().replaceAll(
          _whitespace,
          ' ',
        );
      }
    }

    final buffer = StringBuffer();
    for (final entry in canonicalHeadersMap.entries) {
      buffer.write('${entry.key}:${entry.value}\n');
    }

    return (buffer.toString(), canonicalHeadersMap.keys.join(';'));
  }

  @override
  String toString() {
    return [
      method,
      _getCanonicalUri(url),
      _getCanonicalQuery(queryParameters),
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');
  }

  String get hash => sha256.convert(utf8.encode(toString())).toString();

  static String _getCanonicalUri(Uri url) {
    if (url.path.isEmpty) return '/';
    final encodedSegments = url.pathSegments.map(_aws4UrlEncode);
    return '/${encodedSegments.join('/')}';
  }

  static String _getCanonicalQuery(
    Map<String, List<String>> queryParametersAll,
  ) {
    if (queryParametersAll.isEmpty) return '';

    final canonicalQueryMap = SplayTreeMap<String, List<String>>();
    for (final entry in queryParametersAll.entries) {
      canonicalQueryMap[_aws4UrlEncode(
        entry.key,
      )] = entry.value.map(_aws4UrlEncode).toList()
        ..sort();
    }

    final buffer = StringBuffer();
    var isFirst = true;
    for (final entry in canonicalQueryMap.entries) {
      for (final value in entry.value) {
        if (!isFirst) buffer.write('&');
        buffer.write('${entry.key}=$value');
        isFirst = false;
      }
    }
    return buffer.toString();
  }
}

/// Encodes a query component for AWS Signature Version 4.
///
/// AWS4 requires encoding space as `%20` and encoding special characters
/// like `!`, `'`, `(`, `)`, and `*`.
String _aws4UrlEncode(String value) {
  return Uri.encodeQueryComponent(value).replaceAll('+', '%20');
}
