import 'package:ctx/ctx.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:s3_client/src/error.dart';
import 'package:s3_client/src/model.dart';
import 'package:s3_client/src/request.dart';
import 'package:s3_client/src/sign/signer.dart';
import 'package:sl/sl.dart';

@internal
class S3BaseClient {
  S3BaseClient({
    required this._baseEndpoint,
    required this._httpClient,
    required this._usePathStyle,
    required this._signer,
    required this._logger,
  });

  final Uri _baseEndpoint;
  final http.Client _httpClient;
  final bool _usePathStyle;
  final S3Signer _signer;
  final Logger? _logger;

  Future<http.StreamedResponse> request(
    String method, {
    required String bucket,
    String? key,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    S3RequestBody? body,
    Context? ctx,
  }) async {
    final url = _baseEndpoint.resolveS3Uri(
      usePathStyle: _usePathStyle,
      bucket: bucket,
      key: key,
      queryParameters: queryParameters,
    );

    final reqLogger = _logger?.withAttrs([
      .string('method', method),
      .string('url', url.toString()),
      .string('bucket', bucket),
      if (key != null) .string('key', key),
    ]);

    final stopwatch = Stopwatch()..start();

    if (reqLogger != null) {
      final contentLength = switch (body) {
        S3RequestBodyBytes(:final bytes) => bytes.length,
        S3RequestBodyStream(:final contentLength) => contentLength,
        null => null,
      };
      reqLogger.debug(
        'request',
        ctx: ctx,
        attrs: [
          if (contentLength != null) .int('content_length', contentLength),
        ],
      );
    }

    try {
      final req = switch (body) {
        S3RequestBodyBytes(:final bytes) => S3Request(
          method,
          url,
          ctx: ctx,
        )..bodyBytes = bytes,
        S3RequestBodyStream(:final contentLength) => S3StreamedRequest(
          method,
          url,
          ctx: ctx,
        )..contentLength = contentLength,
        null => S3Request(method, url, ctx: ctx),
      };

      if (headers != null) req.headers.addAll(headers);
      await _signer.sign(req);

      final responseFuture = _httpClient.send(req);

      if (body case S3RequestBodyStream(:final stream)) {
        req as S3StreamedRequest;

        try {
          await req.sink.addStream(stream);
        } finally {
          await req.sink.close();
        }
      }

      final response = await responseFuture;

      stopwatch.stop();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final bodyString = await response.stream.bytesToString();
        S3Error s3Error;
        try {
          s3Error = S3Error.fromXmlDocument(bodyString);
        } catch (_) {
          s3Error = S3Error(
            code: response.statusCode.toString(),
            message: bodyString.isNotEmpty
                ? bodyString
                : (response.reasonPhrase ?? 'Unknown S3 error'),
          );
        }

        final exception = S3Exception.fromError(s3Error);
        reqLogger?.warn(
          'response',
          ctx: ctx,
          attrs: [
            .int('status_code', response.statusCode),
            .int('duration_ms', stopwatch.elapsedMilliseconds),
            .string('error_code', s3Error.code),
            .string('error_message', s3Error.message),
          ],
        );
        throw exception;
      }

      reqLogger?.debug(
        'response',
        ctx: ctx,
        attrs: [
          .int('status_code', response.statusCode),
          .int('duration_ms', stopwatch.elapsedMilliseconds),
        ],
      );

      return response;
    } on S3Exception catch (error, stackTrace) {
      Error.throwWithStackTrace(error, stackTrace);
    } catch (error, stackTrace) {
      stopwatch.stop();

      final effectiveError = error is http.RequestAbortedException
          ? (ctx?.error ?? error)
          : error;

      reqLogger?.error(
        'response',
        ctx: ctx,
        attrs: [
          .int('duration_ms', stopwatch.elapsedMilliseconds),
          .error(effectiveError),
          .stackTrace(stackTrace),
        ],
      );

      Error.throwWithStackTrace(effectiveError, stackTrace);
    }
  }

  Future<Uri> presign(
    String method, {
    required String bucket,
    required String key,
    Duration expires = const Duration(minutes: 15),
    Map<String, String>? queryParameters,
    Context? ctx,
  }) {
    final url = _baseEndpoint.resolveS3Uri(
      usePathStyle: _usePathStyle,
      bucket: bucket,
      key: key,
      queryParameters: queryParameters,
    );

    _logger?.debug(
      'presign',
      ctx: ctx,
      attrs: [
        .string('method', method),
        .string('bucket', bucket),
        .string('key', key),
        .int('expires_sec', expires.inSeconds),
      ],
    );

    return _signer.presign(method, url, expires: expires);
  }
}

extension on Uri {
  Uri resolveS3Uri({
    required bool usePathStyle,
    required String bucket,
    required String? key,
    required Map<String, String>? queryParameters,
  }) {
    final effectiveQueryParams = queryParameters?.isEmpty ?? true
        ? null
        : queryParameters;

    final keySegments = key?.split('/');

    if (usePathStyle) {
      return replace(
        pathSegments: [...pathSegments, bucket, ...?keySegments],
        queryParameters: effectiveQueryParams,
      );
    } else {
      return replace(
        host: '$bucket.$host',
        pathSegments: keySegments,
        queryParameters: effectiveQueryParams,
      );
    }
  }
}
