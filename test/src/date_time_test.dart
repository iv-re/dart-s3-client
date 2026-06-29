import 'package:s3_client/src/sign/date_time.dart';
import 'package:test/test.dart';

void main() {
  group('S3DateTime', () {
    test('converts local DateTime to UTC', () {
      final local = DateTime(2026, 6, 23, 12, 10, 21);
      final s3DateTime = S3DateTime(local);
      expect(s3DateTime.isUtc, isTrue);
      expect(s3DateTime.dateTime, local.toUtc());
    });

    test('retains UTC for UTC DateTime', () {
      final utc = DateTime.utc(2026, 6, 23, 12, 10, 21);
      final s3DateTime = S3DateTime(utc);
      expect(s3DateTime.isUtc, isTrue);
      expect(s3DateTime.dateTime, utc);
    });

    test('now() creates UTC DateTime', () {
      final s3DateTime = S3DateTime.now();
      expect(s3DateTime.isUtc, isTrue);
    });

    test('toIso8601Basic formats correctly', () {
      final date = DateTime.utc(2026, 6, 23, 7, 10, 35);
      final s3DateTime = S3DateTime(date);
      expect(s3DateTime.toIso8601Basic(), '20260623T071035Z');
    });

    test('toIso8601BasicDate formats correctly', () {
      final date = DateTime.utc(2026, 6, 23, 7, 10, 35);
      final s3DateTime = S3DateTime(date);
      expect(s3DateTime.toIso8601BasicDate(), '20260623');
    });
  });
}
