import 'package:flutter_test/flutter_test.dart';
import 'package:playup/leaderboard_domain.dart';

void main() {
  group('isLeaderboardProfileEligible', () {
    test('keeps a normal public player', () {
      expect(
        isLeaderboardProfileEligible({'displayName': 'Tariq', 'xp': 120}),
        isTrue,
      );
    });

    test('filters profiles flagged as test, demo, or guest', () {
      for (final flag in ['isTest', 'isDemo', 'isGuest']) {
        expect(
          isLeaderboardProfileEligible({'displayName': 'Player One', flag: true}),
          isFalse,
          reason: '$flag profiles are not public leaderboard entries',
        );
      }
    });

    test('filters empty and placeholder names', () {
      for (final name in ['', '   ', 'Player', 'Guest Player', 'Demo player']) {
        expect(
          isLeaderboardProfileEligible({'displayName': name}),
          isFalse,
          reason: '"$name" is not a real public player name',
        );
      }
    });

    test('filters dummy labels while preserving ordinary names', () {
      expect(
        isLeaderboardProfileEligible({'displayName': 'UAT Sample'}),
        isFalse,
      );
      expect(
        isLeaderboardProfileEligible({'displayName': 'Test Player'}),
        isFalse,
      );
      expect(
        isLeaderboardProfileEligible({'displayName': 'Sam Player'}),
        isTrue,
      );
    });
  });
}
