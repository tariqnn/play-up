# PlayUp mobile release audit

Audit date: 17 October 2026  
Scope: current Flutter source, production Firebase/website data, Android emulator flow, local release artifacts, and available CI status.

## Current result

**Not ready for public release yet.** Venue discovery and the map work in the current Android emulator build. The map crash found during this audit is fixed. All five live Infinity courts are intentionally contact-only because rates and availability have not been confirmed; direct court reservations therefore remain disabled. A signed Android release bundle is built locally, but current Apple TestFlight and Google Play uploads/review status were not verified in this session.

## Verified app and data state

- The Android emulator loaded the real Infinity 3x3 listing and image. Opening the map rendered Amman OpenStreetMap tiles, the court marker/list, and visible attribution. A runtime crash caused by passing immutable HTTP headers to `flutter_map` was fixed in commit `3836bf3` on `uat-admin-platform-readiness`.
- `BookScreen` reads the live Firestore courts catalogue. Release builds reject the Firebase Emulator flag, and test fixtures are only seeded when emulator mode is explicitly enabled.
- Firestore readback: 1 active academy; 5 active courts, all with coordinates and all contact-only; 10 user profiles with no test-like identities; 3 public profiles with no test-like identities. The root collection list contains no `matches` or `leaderboard` collection. One legacy anonymous guest profile remains; it has no public profile or subcollections and was not classified as test/demo, so it was preserved.
- Firebase Auth readback after cleanup: 34 accounts and no accounts matching the test/demo/UAT indicators. One account whose email local part was exactly `test` had no Firestore user profile, public profile, bookings, matches, or subcollections. It was deleted and the Auth readback confirmed it was gone.
- Firestore Rules Emulator passed 13/13 tests in the current worktree, including the signed-participant booking-list query shape (`participants array-contains` plus `startUtc` ordering). This is rules/query verification; a real signed-in customer booking-history session was not available for end-to-end verification.
- Production website database audit: healthy; 7 venues, 0 demo venues, 0 future games, 1 academy, 0 activities, 0 offers, 0 tournaments, and 0 community posts. Live `/venues`, `/venues/map`, `/games`, and `/leaderboards` returned HTTP 200. Unauthenticated `/bookings` redirected to login.
- The website has one administrator account using a placeholder `.local` email. It has elevated access and six linked records, so it was preserved. Replace it with the real operator’s admin email before public launch.

## Build verification

- `flutter analyze --no-pub`: passed with no issues.
- `flutter test --no-pub`: passed 23/23 tests, including a regression test that constructs the native map tile layer with PlayUp request headers.
- Release APK, AAB, and Flutter web builds completed from the corrected source. Android version is `1.0.0+4`; APK and AAB signatures match the existing PlayUp release certificate. The AAB contains all four Infinity court photos.
- GitHub reports the Vercel status as successful for the current branch head. No CodeMagic check run or current App Store Connect/Play Console upload was verified here.

## Remaining release blockers

1. Replace the sole website administrator’s `.local` email with a real, monitored operator account. Do not delete the existing elevated account until access is safely transferred.
2. Configure production password-reset email through the chosen mail provider. The current production audit reports reset email as unconfigured; its provider secret must be added directly in Vercel Production settings.
3. Set the exact registered legal operator name and address. These production fields are currently unconfigured.
4. Keep Infinity courts contact-only until the operator supplies verified rates and bookable hours. Do not publish guessed prices or availability.
5. Complete a real signed-in booking-history check and physical-device acceptance when a real test account/device is available. The query/rules pass does not substitute for that customer-session test.
6. Verify the current iOS TestFlight and Google Play states, including the latest uploaded build and store-review submission. The local APK/AAB are not evidence of a store upload.
7. Recheck store listing, age/privacy declarations, app links, and required device screenshots in the current consoles before submission; their current status was not verified in this audit.

The 16 October audit has been superseded; do not use its catalogue and build-number conclusions.
