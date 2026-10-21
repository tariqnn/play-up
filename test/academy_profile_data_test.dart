import 'package:flutter_test/flutter_test.dart';
import 'package:playup/academy_profile_data.dart';

void main() {
  group('academyFieldList', () {
    test('keeps array values', () {
      expect(academyFieldList(['Basketball', 'Padel']), [
        'Basketball',
        'Padel',
      ]);
    });

    test('wraps legacy string values', () {
      expect(academyFieldList('Basketball, Padel'), ['Basketball, Padel']);
    });

    test('handles null and empty values', () {
      expect(academyFieldList(null), isEmpty);
      expect(academyFieldList('  '), isEmpty);
    });
  });
}
