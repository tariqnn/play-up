import 'package:flutter_test/flutter_test.dart';
import 'package:playup/booking_presentation.dart';

void main() {
  final now = DateTime.utc(2026, 9, 6, 12);
  test('cancelled bookings stay separate regardless of their date', () {
    for (final end in [
      now.subtract(const Duration(days: 1)),
      now.add(const Duration(days: 1)),
    ]) {
      expect(
        bookingViewFor(status: 'cancelled', end: end, now: now),
        BookingView.cancelled,
      );
    }
  });
  test('completed and expired bookings belong in past', () {
    expect(
      bookingViewFor(
        status: 'completed',
        end: now.add(const Duration(days: 1)),
        now: now,
      ),
      BookingView.past,
    );
    expect(
      bookingViewFor(status: 'confirmed', end: now, now: now),
      BookingView.past,
    );
    expect(
      bookingViewFor(
        status: 'checkedIn',
        end: now.subtract(const Duration(minutes: 1)),
        now: now,
      ),
      BookingView.past,
    );
  });
  test('active bookings remain upcoming until their end time', () {
    expect(
      bookingViewFor(
        status: 'confirmed',
        end: now.add(const Duration(minutes: 1)),
        now: now,
      ),
      BookingView.upcoming,
    );
    expect(
      bookingViewFor(status: 'pending', end: null, now: now),
      BookingView.upcoming,
    );
  });
  test('internal statuses have readable labels and an honest fallback', () {
    expect(bookingStatusLabel('pending'), 'Awaiting confirmation');
    expect(bookingStatusLabel('checkedIn'), 'Checked in');
    expect(bookingStatusLabel('unknown'), 'Status unavailable');
  });
}
