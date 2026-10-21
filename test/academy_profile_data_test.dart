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

  group('academyPackageList', () {
    test('normalizes package maps and legacy package names', () {
      expect(
        academyPackageList(
          [
            {'title': 'Junior training', 'price': 25},
            {'title': '   '},
            'Casual sessions',
            42,
          ],
          legacyNames: ['Junior training', 'Adult skills'],
        ),
        [
          {'title': 'Junior training', 'price': 25},
          {'title': 'Casual sessions'},
          {'title': 'Adult skills'},
        ],
      );
    });

    test('ignores malformed values instead of throwing', () {
      expect(academyPackageList(42, legacyNames: null), isEmpty);
      expect(academyPackageList([null, 4, {}]), isEmpty);
    });
  });

  group('academyImageList', () {
    test('keeps trimmed non-empty image urls', () {
      expect(academyImageList([' https://img.test/a.jpg ', '', null, 3]), [
        'https://img.test/a.jpg',
      ]);
    });

    test('accepts a legacy scalar url', () {
      expect(academyImageList(' https://img.test/cover.jpg '), [
        'https://img.test/cover.jpg',
      ]);
    });
  });
}
