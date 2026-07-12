# Known issues and external limitations

- Real payment capture/refunds are unavailable: no payment provider SDK/account or refund API exists.
- SMS/email and server-scheduled reminders are unavailable: no provider or trusted Cloud Functions backend exists.
- Privileged UAT users cannot be seeded safely from an untrusted client; create them with Firebase Admin tooling using credentials kept outside Git.
- iOS release build/signing must run on macOS with an Apple developer team.
- Firestore rule emulator integration tests require the Firebase CLI and a configured Java runtime; pure domain tests are included in this repository.
- Current catalog samples predate tenant IDs and must be replaced by tenant-tagged UAT records before academy CRUD testing.
- Court prices are still represented as display strings in the legacy catalog; authoritative server-side price/promotion calculation requires a trusted backend and a numeric pricing schema.
- Several legacy academy analytics/booking-management views render bundled sample rows. They must be migrated to tenant-scoped Firestore queries before real UAT sign-off.
