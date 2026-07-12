# UAT readiness report

Architecture: Flutter Material 3 client for iOS, Android and web; Firebase Authentication, Firestore, Storage, Messaging and Analytics. Firestore is the data/API boundary.

Implemented in this hardening pass: granular role model, immutable self-service privileges, tenant-isolated rules, portal visibility, transactional slot locks, booking transition policy, matchmaking validation policy, persistent customizable dashboards, append-only audit boundary, safe environment template and automated domain tests.

Verification completed: formatting, `flutter analyze`, 8 Flutter tests, Firestore emulator rule compilation, and the release web build pass.

Status: **READY FOR UAT**.

The missing trusted boundary is now implemented with Firebase Cloud Functions. Booking prices use integer minor units, promotions are server validated, slot locks and booking status transitions are transactional, matchmaking mutations are server controlled, audit and in-app notification records are generated, and protected UAT account/data seeding is available. Academy court, booking/check-in, and analytics workflows now use authenticated tenant-scoped Firestore queries.

Release verification: Flutter analysis and 8 tests pass; 4 backend domain tests pass; 4 Firestore authorization tests pass in the emulator; dependency audits report zero vulnerabilities; release web and Android APK builds succeed. Native iOS icons are generated in every required size; compiling/signing the iOS binary remains a macOS/App Store credential operation.
