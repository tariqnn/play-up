import 'package:flutter_test/flutter_test.dart';
import 'package:playup/booking_domain.dart';

void main() {
  final day = DateTime.utc(2026, 7, 13);

  test('valid booking status transitions are enforced', () {
    expect(
      BookingPolicy.canTransition(
        BookingStatus.confirmed,
        BookingStatus.checkedIn,
      ),
      isTrue,
    );
    expect(
      BookingPolicy.canTransition(
        BookingStatus.completed,
        BookingStatus.confirmed,
      ),
      isFalse,
    );
  });

  test('blocked and maintenance periods cannot be booked', () {
    expect(
      () => BookingPolicy.validateSlot(
        startUtc: day.add(const Duration(hours: 12)),
        endUtc: day.add(const Duration(hours: 13)),
        nowUtc: day,
        openingUtc: day.add(const Duration(hours: 8)),
        closingUtc: day.add(const Duration(hours: 22)),
        blocked: [
          (
            start: day.add(const Duration(hours: 12, minutes: 30)),
            end: day.add(const Duration(hours: 14)),
          ),
        ],
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });

  test('matchmaking prevents duplicates and capacity overflow', () {
    expect(
      () => MatchmakingPolicy.validateJoin(
        userId: 'p1',
        players: {'p1'},
        capacity: 2,
        suspended: false,
        hasConflict: false,
        status: 'open',
      ),
      throwsA(isA<DomainValidationException>()),
    );
    expect(
      () => MatchmakingPolicy.validateJoin(
        userId: 'p3',
        players: {'p1', 'p2'},
        capacity: 2,
        suspended: false,
        hasConflict: false,
        status: 'open',
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });
}
