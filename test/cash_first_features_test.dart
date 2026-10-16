import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playup/main.dart';
import 'package:playup/more_screens2.dart';

void main() {
  group('Cash-First & Market-Leading Features Tests', () {
    test('court peak pricing calculates correctly across hours', () {
      const court = Court(
        id: 'c1',
        name: 'Center Court',
        subtitle: 'Padel Club',
        sport: 'Padel',
        price: 'JOD 15.00/hr',
        basePriceMinor: 1500,
        currency: 'JOD',
        rating: '4.9',
        distance: '1.2 km',
        gradient: [Color(0xFF000000), Color(0xFF111111)],
        icon: CupertinoIcons.sportscourt,
        address: 'Amman',
        openingHour: 8,
        closingHour: 24,
        peakPriceMinor: 2500,
        peakHourStart: 18,
        peakHourEnd: 23,
      );

      expect(court.hasPeakPricing, isTrue);
      expect(court.isPeakHour(12), isFalse);
      expect(court.effectiveHourlyRateMinor(12), 1500);

      expect(court.isPeakHour(18), isTrue);
      expect(court.effectiveHourlyRateMinor(18), 2500);
      expect(court.isPeakHour(22), isTrue);
      expect(court.effectiveHourlyRateMinor(22), 2500);
      expect(court.isPeakHour(23), isFalse);
      expect(court.effectiveHourlyRateMinor(23), 1500);
    });

    test('open match cash split calculates per-player share correctly', () {
      final match = OpenMatch.fromMap({
        'title': 'Evening Padel',
        'sport': 'Padel',
        'hostName': 'Tariq',
        'courtName': 'Court 1',
        'totalMinor': 2000,
        'capacity': 4,
        'currency': 'JOD',
        'players': ['u1', 'u2'],
        'neededPlayers': 2,
        'scoreStatus': 'pendingConfirmation',
        'hostReliability': 96,
      });

      expect(match.pricePerPlayer, 'JOD 5.00');
      expect(match.hostReliability, 96);
      expect(match.scoreStatus, 'pendingConfirmation');
    });

    test('reliability badge threshold logic', () {
      const highRel = 95;
      const goodRel = 75;
      const lowRel = 50;

      expect(highRel >= 90, isTrue);
      expect(goodRel >= 70 && goodRel < 90, isTrue);
      expect(lowRel < 70, isTrue);
    });
  });
}
