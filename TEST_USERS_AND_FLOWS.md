# PlayUp test users

All test accounts use:

`PlayUp123!`

| Account | Email | Purpose |
| --- | --- | --- |
| Platform admin | `admin@playup.test` | Admin website and all platform modules |
| Academy owner | `academy.owner@playup.test` | Academy dashboard and court creation |
| Academy staff | `academy.staff@playup.test` | Tenant booking and check-in operations |
| Player one | `player.one@playup.test` | Booking owner and friend requester |
| Player two | `player.two@playup.test` | Friend recipient and invite joiner |

The academy-owner account intentionally asks for a new password on first sign-in. Use `PlayUp123!` once, then choose a replacement. The test academy contains no dummy courts; create a real court with a real location and photo before testing booking.

## Full acceptance flow

### Admin and academy onboarding

1. Sign into the admin website as `admin@playup.test`.
2. Open **Academies**, select **Add academy**, and enter the academy plus owner fields.
3. Copy the displayed temporary password.
4. Sign into the mobile app as the new owner and verify that PlayUp requires a replacement password.
5. Sign in again and verify that the academy dashboard opens.

### Court, location, image and map

1. Sign in as the academy owner.
2. Open **Court management** and select **Add court**.
3. Enter the court data, select its exact point on the map, and choose a gallery photo.
4. Save and verify that the court appears in the player court list and map.
5. Verify that editing the court preserves its academy assignment.

### Booking and availability

1. Sign in as `player.one@playup.test`.
2. Open the real court, choose a future date, duration, and available time.
3. Confirm the cash-at-venue booking and verify that a booking ID is returned.
4. Open the same court again. Every overlapping 30-minute period must be red and unavailable.
5. Try the same period as `player.two@playup.test`; PlayUp must reject the overlap.

### Friends

1. As player one, open **Profile → Friends → Suggested**.
2. Add **Test Player Two**.
3. As player two, open **Profile → Friends → Requests** and accept.
4. Return to **Friends** on both accounts and verify the connection.

### Booking invites

1. As player one, open the booking confirmation and select **Invite friends**.
2. Share or copy the generated link.
3. Open the link while signed in as player two.
4. Verify the joined confirmation and that player two appears in the booking participants.
5. Open the same link again and verify that duplicate joining is refused.

### Appearance and navigation

1. On the sign-in page, switch between System, Light and Dark.
2. In Dark, verify a true black background and dark booking cards with no white boxes.
3. Navigate forward and back through court, slot, setup and payment screens.
4. Verify native slide/back behavior and that bottom tabs keep their state.

### Achievements

1. Compare the two player accounts before booking; progress should differ only by live data.
2. Complete eligible bookings/matches and reopen **Achievements**.
3. Verify that booking, match, streak, host, rating and academy-loyalty progress are calculated from that account’s own records.

### Apple sign-in

Apple is intentionally hidden until the Apple provider is configured in Firebase and an Apple Developer Service ID/key is supplied. After configuration, build with `--dart-define=APPLE_SIGN_IN_ENABLED=true` on iOS and test success, cancellation, and private-email relay.
