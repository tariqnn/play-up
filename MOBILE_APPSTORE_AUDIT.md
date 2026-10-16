# PlayUp mobile release audit

Audit date: 16 October 2026

## Current result

**Not ready for public release or store review.** The app code passes analysis and unit/widget tests, and a signed Android App Bundle is being rebuilt. Apple build 14 is available to the internal TestFlight group. The production venue catalogue contains only test/UAT records, so the app has no verified playable venues. Google Play's required store listing is incomplete; its review/publishing action is not available yet. The iOS App Store version is still `Prepare for Submission`.

## Verified build and account state

- `flutter analyze`: passed with no issues.
- `flutter test`: passed, 20 tests.
- Android release AAB: rebuilt as version code 2 from the current working tree; output is `build/app/outputs/bundle/release/app-release.aab`. Upload to Play Console is not verified.
- Android target API is 36. New Play submissions must target API 36 or later as of 31 August 2026 ([Google Play target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)).
- App Store Connect app `play-up`: version 1.0 is `Prepare for Submission`; build 14 (1.0.0) is selected and is assigned to the internal `testing` group. The build is available to its current internal tester. No new iOS build containing the latest working-tree change has been created or uploaded.
- Codemagic workflow `ios-testflight` runs on pushes to `uat-admin-platform-readiness` and submits successful builds to TestFlight. A prior run uploaded build 14 but ended with a beta-review post-processing error; build 14 was processed and assigned internally after the export-compliance response was completed in App Store Connect.
- Play Console saved the 18+ target audience and core declarations. The dashboard still presents `Set up your store listing`; phone screenshots are required and missing. No Play release has been sent for review.
- Play Console closed testing has 0 opted-in testers. This personal developer account must run a closed test with at least 12 opted-in testers for 14 continuous days before it can apply for production access ([Google Play testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en)).

## Release blockers

1. **No verified production inventory.** Firebase `sports-app-257a0` has academy records, but the inspected academy and court documents are test/UAT entries. The three court documents are associated with `playup-test-academy`, `uat-academy-a`, and `uat-academy-b`. There is no verified Infinity Sports court record. The live app correctly shows “No venues found.”
2. **Court prices and booking hours are not published for Infinity Sports.** The official site verifies its Amman location, contact details, and facilities/programs, but most basketball pricing is “Contact for pricing.” The volleyball course price is not a court-booking rate. Do not create bookable courts with guessed prices or schedules. [Official facilities](https://www.infinitysportsjo.com/facilities/) · [Official programs](https://www.infinitysportsjo.com/programs/)
3. **Play Store listing is incomplete.** Google Play requires phone screenshots. Do not use fixture-generated screenshots or screenshots implying venue availability that does not exist.
4. **Google Play production is time-gated.** A closed test and 14 days with 12 opted-in testers are required before production access; this cannot be completed today for a new personal developer app.
5. **Public age language and app audience differ.** Play is configured for 18+, but the public Terms allow users from 16 with parental/guardian involvement. The app has no age gate. Align the app, legal pages, and Play declaration before review.
6. **Social moderation label overstated capability.** The former “Report or Block Player” control only opens a support ticket and does not block the selected player. The UI label has been changed to “Report Player”; a real block feature is not implemented.
7. **Deep links are misconfigured.** Android/iOS app links use `playup.app`; the production domain is `play-up.fit`. Android Digital Asset Links and Apple App Site Association files contain placeholder identifiers, and the corresponding live domain routes were verified as unavailable. Do not claim verified universal links.
8. **Privacy disclosures need a final runtime reconciliation.** App Store privacy declarations and Play Data Safety must match actual Firebase Auth/Firestore, location/Nominatim, messaging, chat, and account deletion behavior. The public policy should identify the relevant processors and retention/deletion practices accurately.
9. **Physical device acceptance is incomplete.** Android emulator startup was checked, but live booking, match chat, account deletion, and iOS device flows were not verified end to end on the release candidate.

## Implemented during this audit

- Changed the match chat button from “Report or Block Player” to “Report Player” so the UI does not claim an unimplemented blocking action.
- Confirmed the feature tests and static analysis still pass after that change.
- Rebuilt the Android AAB for version code 2. It remains local and has not been uploaded.

## Next steps needed for a reviewable release

1. Obtain authorized Infinity Sports court prices, opening/booking hours, court names, and availability; add only verified values to the live catalogue.
2. Resolve the 18+ age policy consistently in the app and public Terms.
3. Complete and verify app-link association files for `play-up.fit` using the real signing certificate and Apple Team ID.
4. Capture and upload genuine phone screenshots after production venue data and core flows are validated.
5. Reconcile and submit the privacy/data-safety declarations; complete Apple's trader status for any intended EU distribution.
6. Upload the Android bundle to a closed test, collect 12 opted-in testers, and keep the test active for 14 days before applying for production access.
7. Produce a fresh iOS build from the corrected source, validate it on a physical iPhone, then submit the completed version for App Review.

The current local AAB and the existing internal TestFlight build are builds, not Google Play/App Store review submissions or public releases.
