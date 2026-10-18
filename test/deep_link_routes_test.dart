import 'package:flutter_test/flutter_test.dart';
import 'package:playup/deep_link_routes.dart';

void main() {
  group('parsePlayUpInvite', () {
    test('parses the production booking invite link', () {
      final invite = parsePlayUpInvite(
        Uri.parse('https://play-up.fit/join/booking/123456789012345678901234'),
      );

      expect(invite?.type, PlayUpInviteType.booking);
      expect(invite?.id, '123456789012345678901234');
    });

    test('parses custom scheme booking links', () {
      final invite = parsePlayUpInvite(
        Uri.parse('playup://booking/123456789012345678901234'),
      );

      expect(invite?.type, PlayUpInviteType.booking);
    });

    test('parses production and custom scheme match links', () {
      final webInvite = parsePlayUpInvite(
        Uri.parse('https://play-up.fit/join/match/match_123'),
      );
      final appInvite = parsePlayUpInvite(
        Uri.parse('playup://match/match_123'),
      );

      expect(webInvite?.type, PlayUpInviteType.match);
      expect(webInvite?.id, 'match_123');
      expect(appInvite?.id, 'match_123');
    });

    test('rejects unrelated hosts and malformed invite IDs', () {
      expect(
        parsePlayUpInvite(Uri.parse('https://playup.app/join/match/abc')),
        isNull,
      );
      expect(
        parsePlayUpInvite(Uri.parse('https://play-up.fit/join/booking/short')),
        isNull,
      );
      expect(parsePlayUpInvite(Uri.parse('playup://unknown/abc')), isNull);
    });
  });
}
