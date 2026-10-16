enum BookingView { upcoming, past, cancelled }

String bookingStatusLabel(String status) => switch (status) {
  'pending' => 'Awaiting confirmation',
  'confirmed' => 'Confirmed',
  'checkedIn' => 'Checked in',
  'completed' => 'Completed',
  'cancelled' => 'Cancelled',
  _ => 'Status unavailable',
};

BookingView bookingViewFor({
  required String status,
  required DateTime? end,
  required DateTime now,
}) {
  if (status == 'cancelled') return BookingView.cancelled;
  if (status == 'completed' || (end != null && !end.isAfter(now))) {
    return BookingView.past;
  }
  return BookingView.upcoming;
}
