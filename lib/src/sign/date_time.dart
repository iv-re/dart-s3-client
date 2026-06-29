import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

/// A wrapper around [DateTime] representing a UTC timestamp
/// formatted for S3 APIs.
@internal
extension type S3DateTime._(DateTime dateTime) implements DateTime {
  S3DateTime(DateTime dateTime) : dateTime = dateTime.toUtc();

  S3DateTime.now() : dateTime = clock.now().toUtc();

  /// Formats the timestamp as an ISO 8601 basic string (YYYYMMDDTHHMMSSZ).
  String toIso8601Basic() {
    return '${year.toFourDigits()}'
        '${month.toTwoDigits()}'
        '${day.toTwoDigits()}T'
        '${hour.toTwoDigits()}'
        '${minute.toTwoDigits()}'
        '${second.toTwoDigits()}Z';
  }

  /// Formats the timestamp as an ISO 8601 basic date-only string (YYYYMMDD).
  String toIso8601BasicDate() {
    return '${year.toFourDigits()}'
        '${month.toTwoDigits()}'
        '${day.toTwoDigits()}';
  }
}

extension on int {
  String toTwoDigits() => toString().padLeft(2, '0');
  String toFourDigits() => toString().padLeft(4, '0');
}
