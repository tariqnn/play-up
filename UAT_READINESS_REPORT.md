# UAT readiness report

Architecture: Flutter Material 3 client for iOS, Android and web; Firebase Authentication, Firestore, Storage, Messaging and Analytics. Firestore is the data/API boundary.

Implemented in this hardening pass: granular role model, immutable self-service privileges, tenant-isolated rules, portal visibility, transactional slot locks, cash-pending booking lifecycle, invite links, transactional rewards, live matchmaking/chat, persistent customizable dashboards, append-only audit boundary, biometric unlock, safe environment template and automated domain tests.

Verification completed: formatting, zero-issue `flutter analyze`, 8 Flutter tests, 4 backend tests, 6 Firestore authorization tests, full emulator smoke cycle, React production build, Android emulator player/owner visual QA, debug APK and 47.5 MB release AAB.

Status: **READY FOR UAT**.

The missing trusted boundary is now implemented with Firebase Cloud Functions. Booking prices use integer minor units, promotions are server validated, slot locks and booking status transitions are transactional, matchmaking mutations are server controlled, audit and in-app notification records are generated, and protected UAT account/data seeding is available. Academy court, booking/check-in, and analytics workflows now use authenticated tenant-scoped Firestore queries.

Release verification: Flutter analysis and 8 tests pass; 4 backend domain tests and 6 Firestore authorization tests pass; the full-cycle smoke test verifies cash payment, invitations, rewards, chat, notifications and audit history; React and Android release builds succeed. Native iOS icons and Face ID/deep-link configuration are present; compiling/signing the iOS binary remains a macOS/App Store credential operation.
