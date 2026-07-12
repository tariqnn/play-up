class DomainValidationException implements Exception {
  const DomainValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum BookingStatus { pending, confirmed, checkedIn, completed, cancelled }

abstract final class BookingPolicy {
  static const transitions = <BookingStatus, Set<BookingStatus>>{
    BookingStatus.pending: {BookingStatus.confirmed, BookingStatus.cancelled},
    BookingStatus.confirmed: {BookingStatus.checkedIn, BookingStatus.cancelled},
    BookingStatus.checkedIn: {BookingStatus.completed},
    BookingStatus.completed: {},
    BookingStatus.cancelled: {},
  };

  static bool canTransition(BookingStatus from, BookingStatus to) =>
      transitions[from]!.contains(to);

  static String slotKey(String courtId, DateTime startUtc) =>
      '${courtId}_${startUtc.toUtc().millisecondsSinceEpoch}';

  static void validateSlot({
    required DateTime startUtc,
    required DateTime endUtc,
    required DateTime nowUtc,
    required DateTime openingUtc,
    required DateTime closingUtc,
    required Iterable<({DateTime start, DateTime end})> blocked,
  }) {
    if (!startUtc.isBefore(endUtc)) {
      throw const DomainValidationException(
        'End time must be after start time.',
      );
    }
    if (!startUtc.isAfter(nowUtc)) {
      throw const DomainValidationException(
        'This time slot has already expired.',
      );
    }
    if (startUtc.isBefore(openingUtc) || endUtc.isAfter(closingUtc)) {
      throw const DomainValidationException(
        'The court is closed at this time.',
      );
    }
    for (final period in blocked) {
      if (startUtc.isBefore(period.end) && endUtc.isAfter(period.start)) {
        throw const DomainValidationException(
          'This time is blocked or reserved for maintenance.',
        );
      }
    }
  }
}

abstract final class MatchmakingPolicy {
  static void validateJoin({
    required String userId,
    required Set<String> players,
    required int capacity,
    required bool suspended,
    required bool hasConflict,
    required String status,
  }) {
    if (suspended) {
      throw const DomainValidationException('Suspended players cannot join.');
    }
    if (status != 'open') {
      throw const DomainValidationException('This match is not open.');
    }
    if (players.contains(userId)) {
      throw const DomainValidationException('You already joined this match.');
    }
    if (players.length >= capacity) {
      throw const DomainValidationException('This match is full.');
    }
    if (hasConflict) {
      throw const DomainValidationException(
        'This match conflicts with another booking or match.',
      );
    }
  }
}
