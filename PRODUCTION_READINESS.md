# PlayUp production readiness

Last engineering review: 17 October 2026.

## Status

The application code is production-hardened and passes the automated release gates listed below. It is **not yet safe to open to public users** until the external configuration and acceptance items in this document are completed against the intended production Firebase, Apple, Google Play, OAuth, domain, and legal accounts.

The live payment model is **cash/pay at venue**. PlayUp does not collect or store card data. Online payments, automatic refunds, SMS, and transactional email beyond Firebase Authentication templates are not part of this release.

## Current readiness update (17 October 2026)

- Fixed the affected Flutter booking/catalog and map loading states, added retry behavior, and built the Flutter web release. `flutter analyze` reports no issues and all 22 Flutter tests pass.
- Ran the release Flutter web app in a mobile-sized browser against production Firebase. Guest venue browsing loaded all five real courts without the prior load error; the Open Map button rendered live OpenStreetMap tiles and the court list, and a court detail showed the explicit “online booking and rates are not configured” state. The temporary anonymous test account was deleted and the follow-up Firebase Auth/Firestore read confirmed 35 Auth users, zero test-marked accounts/records, and no temporary profile.
- Re-read Firebase production data: 12 user documents, 3 public profiles, 3 academies, and 5 real courts; zero matches, bookings, offers, events, or test-marked records. Removed the last orphaned test administrator from Firebase Authentication; the follow-up Auth read found no test-marked accounts (35 Auth users remain).
- The 5 Firebase courts have real coordinates and are intentionally non-bookable until their rates and availability are confirmed. The app offers venue contact instead of inventing a price.
- Deployed the latest PlayUp website to `https://play-up.fit` as Vercel deployment `dpl_BCmQ8bpPgTgRGyCBRZAKpQipnveB`. The map renders OpenStreetMap at the verified Infinity campus coordinates for its five courts; Trax and Ayla retain address-based directions until exact coordinates are verified. Production pages `/venues`, `/venues/map`, `/leaderboards`, and `/games` return HTTP 200 with no page errors or test content.
- The website production database has 7 sourced venues, no future games, no demo venues, and only the administrator account. Booking is deliberately unavailable until venues confirm their rates.
- Current verification: `flutter analyze` reports no issues; `flutter test` passes 22/22; website typecheck, 12 tests, optimized build, and the production Neon audit passed. The audit reports 1 administrator, 7 venues, 0 future games, 0 demo venues, and database health `ok`.
- Latest iOS build `1.0.0 (23)` is visible in App Store Connect TestFlight with status `Ready to Submit` and assigned to the internal `testing` group. Codemagic's post-processing step reported a failure, but Apple's build list confirms the upload is processed and grouped. The existing internal tester can install it from TestFlight; external beta review/public release is not verified or submitted.
- Re-audited production on 17 October: the website now publishes the verified Creative Networks contact email and phone; the fictitious PlayUp support mailbox, phone, business address, social links, and unverified tournament announcement were removed. Production audit remains healthy with 1 administrator, 7 venues, 0 demo venues, 0 future games, and 0 public member accounts. Support email is configured; password-reset email and legal operator name/address are still missing.
- Latest iOS build `1.0.0 (23)` is visible in App Store Connect TestFlight with status `Ready to Submit` and assigned to the internal `testing` group. Codemagic's post-processing step reported a failure, but Apple's build list confirms the upload is processed and grouped. External beta review/public release is not verified or submitted.
- The affected flows have not been exercised in signed-in physical iPhone or Android builds. Production password-reset delivery, legal operator details, a Neon recovery drill, final legal review, store data-safety/privacy declarations, and Android Play release remain outstanding. Court rates and availability are intentionally out of scope for this contact-only launch choice.

## Completed engineering work

- Booking price calculation, time-slot locking, creation, cancellation, status transitions, cash collection, matchmaking mutations, invitations, rewards, and chat writes are server-authoritative Cloud Functions.
- Court slot availability is returned through a bounded authenticated callable; raw lock records and invitation tokens are no longer readable by clients.
- Promotion codes are unique platform-managed records with date, venue, minimum-spend, global-use, and per-user-use enforcement inside the booking transaction.
- Every booking snapshots gross value, discount, platform commission, academy net, payment status, and settlement status. Admin operators can reconcile collected cash without recalculating historical commissions.
- Pending bookings expire and release locks automatically, started matches close automatically, and reminder delivery respects user preferences while pruning invalid push tokens.
- Production clients no longer fall back to direct Firestore writes when a callable is absent. Direct fallbacks are emulator-only.
- Player booking details now use live dates, totals, payment state, participant count, match chat, maps directions, and a real cancellation workflow. Late cancellation fees are calculated on the server.
- Password recovery uses Firebase's signed reset link. Email verification is required before non-anonymous users can use protected features.
- Notification/privacy preferences persist to Firestore. Account deletion removes personal collections, anonymizes retained operational records, removes match participation/messages, and deletes the Auth identity.
- Points, XP, public profiles, bookings, matches, friendships, invites, notifications, audit records, and other trusted data cannot be forged directly by clients.
- Maintenance mode is live in the app and enforced by Cloud Functions for non-platform administrators.
- App Check clients are activated with Play Integrity on Android, App Attest with DeviceCheck fallback on Apple, and reCAPTCHA v3 on web/admin when the site keys are supplied. Deployed callables enforce App Check; emulators do not.
- Academy/court/staff permissions are scoped in UI, Firestore, Storage, and Functions. Owner offer/event changes now persist to academy-scoped Firestore records.
- The platform admin uses a server-side owner-account creation callable and Firebase setup email; it no longer exposes a shared default password or creates Auth users in the browser.
- The admin build fails closed with a clear configuration screen if production Firebase or App Check values are absent. Auth/profile listeners clean up correctly and unsupported direct record mutations are hidden.
- Admin navigation and actions are permission-gated, finance reporting is currency-separated, and support/review editors cannot rewrite customer-authored content.
- Court opening-hour checks use the court's IANA timezone (default `Asia/Amman`) instead of UTC hours.
- Android AAB/APK, Flutter web, and React admin release builds complete. Android artifacts verify with the configured PlayUp upload certificate.

## Usability and correctness pass (5 September 2026)

- Fixed: a pending booking whose cash was already collected at check-in could be auto-expired by the 5-minute cron and have its settlement snapshot zeroed, destroying the collected-cash audit trail. The cron now preserves settlement fields when payment was already collected.
- Fixed: the platform commission silently defaulted to 0% (no error) when a court, academy, and platform config all lacked a commission rate. The server now rejects the booking with a clear configuration error instead of processing it commission-free.
- Fixed: a court configured to close at midnight (`closingHour: 24`) rejected any booking that crossed midnight without ending at exactly 00:00, making genuinely round-the-clock courts unbookable overnight.
- Fixed: platform-initiated cancellations without a supplied reason were mislabeled "Cancelled by venue" in the audit trail; they now record "Cancelled by platform administrator".
- Fixed: if the password-setup email failed after an academy staff Auth account was already created, the owner had no way to resend it short of a duplicate-email error. The mobile app now offers a "Resend" action against the same account instead of requiring account recreation.
- Fixed: the mobile Edit Profile screen showed a hardcoded placeholder name/city ("Alex Mercer", "Location not set") instead of the signed-in user's real name from their sign-in provider.
- Reduced typing across the mobile app: the shared text-field widget now infers OS autofill hints and capitalization from field type/label (name, email, phone, password) across its ~15 call sites; the sign-up form is wrapped for password-manager autofill; the promotion-code field auto-uppercases; academy contact/address fields get the right keyboard and autofill hints; the academy event editor now uses a date picker instead of free-typed text.
- Reduced typing and mistake risk in the admin console: Courts and Promotions no longer require hand-typing a raw academy/court document ID (now searchable dropdowns, cascading academy → court); Support ticket status is now a fixed dropdown; minor-unit currency fields (price, minimum spend, etc.) are now edited as a decimal amount instead of a raw integer; numeric fields have sane min/max guards; the login screen supports password-manager autofill and a "Forgot password?" action; new courts default to the last-used academy.
- Verification re-run after these fixes: `flutter analyze` (0 issues), `flutter test` (9/9), `dart format` (clean), Functions TypeScript build and domain tests (5/5), Firestore emulator authorization tests (12/12), the full Auth/Firestore/Functions emulator lifecycle smoke test (passing end-to-end), `npm audit --omit=dev` for Functions and admin-web (0 vulnerabilities each), and the React admin and Flutter web production builds.

## Production-launch blockers closed (6 September 2026)

- **No safe way to create the first production admin.** Every admin-creation path (`createManagedOwnerAccount`, `createAcademyStaff`, the admin console) requires the caller to already be a superAdmin — a brand-new production project had no account able to call them. Added `functions/scripts/bootstrap-super-admin.js` (`npm --prefix functions run bootstrap:super-admin`), an operator-run Admin SDK script that refuses to run if any superAdmin already exists, creates exactly one account with an unknown random password, and prints a one-time Firebase password-setup link. Verified against the emulator: creates the account on first run, and correctly refuses on a second run once one exists.
- **Universal/App Links were silently undeployable.** `firebase.json`'s hosting `ignore` list (`"**/.*"`) excluded any `.well-known` directory from every deploy, so even fully configured Apple App Site Association / Android `assetlinks.json` files would never reach production — booking invite deep links would never verify on real devices. Fixed the ignore list to keep `.well-known/**`, added explicit `Content-Type: application/json` headers for both files, and added template files at `web/.well-known/apple-app-site-association` and `web/.well-known/assetlinks.json` pre-filled with this app's real bundle ID (`com.playup.playu`) and package name (`com.playup.playup`) — only the Apple Team ID and the Android signing SHA-256 fingerprint still need to be filled in once those are known (see item 6 below).
- **No legal document content existed.** `PRIVACY_POLICY_DRAFT.md` and `TERMS_OF_SERVICE_DRAFT.md` are new engineering-authored starting drafts covering this app's actual data flows and business rules (location, cash-only payment, late-cancellation fee, chat, rewards, account deletion/anonymization). They are explicitly marked as drafts requiring qualified legal review before publishing at the URLs in item 5 below — they close the "there is nothing to review" gap, not the legal-review requirement itself.
- Fixed a duplicate `VITE_USE_EMULATORS` line in `admin-web/.env.example`.

## Mandatory launch work outside this repository

Complete every item before public launch:

1. **Production Firebase**
   - Select a dedicated production project and Blaze billing plan.
   - Regenerate `firebase_options.dart`, Android `google-services.json`, and the iOS Firebase configuration for the final package/bundle IDs.
   - Deploy Functions, Firestore rules/indexes, Storage rules, and the intended Hosting targets.
   - Create the first super administrator with `npm --prefix functions run bootstrap:super-admin` (see the script header for required environment variables); never seed UAT users/data into production.

2. **App Check**
   - Register the Android app and signing SHA-256 for Play Integrity.
   - Register the iOS app for App Attest/DeviceCheck.
   - Create separate reCAPTCHA v3 keys for the player web app and admin origin.
   - Supply `FIREBASE_APP_CHECK_WEB_KEY` and `VITE_FIREBASE_APP_CHECK_KEY`, verify valid tokens in monitoring mode, then enforce Firestore, Storage, Auth where supported, and Functions.

3. **Authentication providers**
   - The final iOS bundle ID is currently `com.playup.playu`; create an iOS Google OAuth client for that exact ID, add its reversed client URL scheme to `Info.plist`, and build with `--dart-define=GOOGLE_IOS_CLIENT_ID=...`.
   - Configure Sign in with Apple in Apple Developer and Firebase, add the required capability/keys, then build with `--dart-define=APPLE_SIGN_IN_ENABLED=true`.
   - Configure authorized domains and branded Firebase email verification/password-reset templates.
   - Verify anonymous authentication is enabled if “Continue as Guest” will remain visible.

4. **Push notifications**
   - Upload the APNs authentication key to Firebase, enable the Apple push/background capabilities, and verify foreground/background/terminated delivery on real iOS and Android devices.

5. **Legal and privacy**
   - Have counsel review and finalize `PRIVACY_POLICY_DRAFT.md` and `TERMS_OF_SERVICE_DRAFT.md` (fill in every `[bracketed]` placeholder, confirm the late-cancellation fee policy with the business owner), then publish the final versions as web pages at `https://playup.app/privacy` and `https://playup.app/terms` (or override the URLs with the `PRIVACY_POLICY_URL`/`TERMS_OF_SERVICE_URL` Dart defines).
   - Obtain legal review for location, account deletion/anonymized booking retention, minors, user-generated chat/reports, rewards, late-cancellation fees, and Jordan/target-market consumer requirements.
   - Complete Apple privacy nutrition labels and Google Play Data Safety declarations from the final data inventory.

6. **Domain and deep links**
   - Control `playup.app` and point it at this Firebase Hosting project.
   - Fill in the two placeholders already scaffolded at `web/.well-known/apple-app-site-association` (Apple Team ID) and `web/.well-known/assetlinks.json` (Android signing SHA-256 fingerprint), then deploy hosting and verify booking invitation links on physical devices. (`firebase.json` was previously misconfigured to silently exclude `.well-known/**` from every deploy — this is now fixed.)

7. **Store and signing operations**
   - Back up the Android upload key and passwords in an encrypted company vault.
   - Build/sign the IPA on macOS/Codemagic with the final Apple team, bundle ID, provisioning profile, and App Store Connect integration.
   - Prepare store listings, screenshots, support URL, privacy URL, content rating, review account, release notes, and staged rollout.

8. **Operations and observability**
   - Configure production support email, maintenance message, default currency, academy commission agreements, court timezone/hours, and real catalog data.
   - Enable budget alerts, quota alerts, Firestore backups/PITR where available, log retention, uptime monitoring, and a crash/error monitoring destination.
   - Document support escalation, refund/late-fee handling, abuse moderation, data-subject requests, and incident rollback.

9. **Acceptance testing**
   - Run the full player, academy owner, court owner, staff, and platform-admin matrix against a production-like staging project on at least one current and one older physical iPhone and Android device.
   - Complete visual, screen-reader, large-text, keyboard, poor-network, offline/reconnect, notification, deep-link, timezone, daylight-saving, and account-deletion tests.
   - Android API 36 emulator QA covered guest discovery, authentication, forced password replacement, onboarding, protected-action gating, court details, private availability, checkout, invalid-promotion recovery, booking creation, history, and details. Repeat the acceptance matrix on physical devices.
   - The in-app browser automation connection was unavailable during this review, so responsive admin visual QA remains a required manual gate even though TypeScript and the Vite production build pass.

## Verified release gates

- `flutter analyze`: no issues.
- `flutter test`: 9/9 passing.
- Functions TypeScript build and domain tests: 5/5 passing.
- Firestore emulator authorization tests: 12/12 passing.
- Full Auth/Firestore/Functions emulator lifecycle: passing, including quote/discount, promotion reuse rejection, 30-minute boundary rejection, concurrent double-booking rejection, private availability, invite joins, cash collection, commission settlement, booking transitions, linked match sync, chat, leave/rejoin, rewards, notifications, and audit records.
- `npm audit --omit=dev` for Functions, admin, and rules tests: 0 known vulnerabilities.
- React/Vite admin production build: passing.
- Flutter Android AAB (60.5 MB) and APK (59.9 MB) release builds: passing and signatures verified.
- Flutter web release build and WebAssembly dry run: passing.
- Android API 36 emulator visual/interaction pass: passing; QA captures are under `build/qa`.

## Release order

1. Finish legal, domain, provider, Firebase, App Check, APNs, and store-account configuration.
2. Deploy to a dedicated staging project and run the complete acceptance matrix.
3. Freeze schema/rules, export a backup, and deploy Functions/rules/indexes/Storage to production.
4. Create production administrators and real academy/court data.
5. Build the signed Android AAB and iOS IPA using production Dart defines and secrets.
6. Run smoke tests against production with internal testers, then use a staged store rollout with monitoring and a rollback owner assigned.

## Current follow-up verification — 18 October 2026

- Vercel production audit: database healthy; 7 venues, 0 demo venues, 0 future games, 1 administrator, and no public member accounts. `/api/health` reports `ok`.
- Production pages `/venues`, `/venues/map`, `/games`, and `/leaderboards` return HTTP 200. The map response includes the OpenStreetMap embed with eager loading. The map also loaded tiles and a court marker in the Android emulator.
- A temporary anonymous Firebase session was used only for signed-in public reads and then deleted. The live Firestore read found 5 active court records, 3 public leaderboard profiles with no test/demo placeholder markers, and 0 open/full matches. All 5 court records belong to Infinity Sports; the facility names match Infinity's published list.
- The deployed `bookings` composite index for `participants` plus `startUtc` is present. `createBooking`, `quoteBooking`, `listAvailableCourts`, `listCourtUnavailableSlots`, and `transitionBooking` are active in `me-central1`. The Firestore rules emulator suite passes 13/13, including the exact participant booking query.
- Current Flutter verification: analyzer clean, 27/27 tests pass, release APK builds and verifies with the configured PlayUp certificate. This does not verify a signed-in production booking session.
- Booking remains contact-only while venue rates and availability are unconfirmed. The live website suppresses Reserve buttons and directs logged-out visitors to login; this is the configured launch behavior.
- Google Play currently says production access is unavailable. Closed testing Alpha 1.0.0 (4) is inactive, and no tester email list is configured. The Protected with Play page reports that Play Integrity API is not integrated; verify App Check attestation using a Play-installed release build before treating callable booking as production-verified.
- The production audit still reports password-reset email and legal operator details as unconfigured. A real signed-in My Bookings load and physical-device release acceptance remain outstanding.

## Live verification refresh — 18 October 2026 (current pass)

- Re-ran the production Neon audit with Vercel production environment: database `ok`; 7 venues, 1 academy, 0 demo venues, 0 future games, 0 activities/offers/tournaments/community posts, and 0 public member accounts. Support email is configured; password-reset delivery and legal operator details are not.
- Re-opened production `/venues/map`: the page renders its OpenStreetMap embed, five coordinate-backed court listings, and directions links. `/games` renders `0 games found`; `/leaderboards` renders no player rows and “No recorded stats yet.” `/bookings` redirects signed-out visitors to the login form as expected for the private route.
- On the installed Android emulator build (version 1.0.0, versionCode 5), the venue detail showed its court photo and the explicit contact-only booking state. **Open directions** launched Google Maps and populated the Infinity Sports Academy destination; Maps then displayed its own first-run location prompt. The in-app map also rendered OpenStreetMap tiles and a venue marker. This verifies map launch and destination handoff, but not live turn-by-turn routing: the emulator reported no network connection and its location setup was incomplete.
- Current workspace checks: `flutter analyze --no-pub` passed; `flutter test --no-pub` passed 34/34; Functions tests passed 9/9; Firestore rules tests passed 13/13 when run against the Firestore emulator. The rules suite covers participant booking reads. The signed-in production booking query was not exercised because no verified player session was available.
- A fresh Firebase Console attempt in this browser was denied for both currently signed-in Google accounts (“project does not exist or you do not have permission”). The latest prior readback recorded in `MOBILE_APPSTORE_AUDIT.md` found the five specifically approved test targets absent and preserved unmatched anonymous users and the separate Store Reviewer account; this pass could not refresh those counts or inspect live Firestore match/profile data.
- Release readiness remains conditional: the venue catalog is intentionally contact-only until rates and availability are confirmed; production password-reset delivery and legal operator identity are unconfigured; Android Play production access/closed-test evidence and Apple TestFlight group assignment remain unverified; and signed-in booking history plus physical-device acceptance remain untested.
- Release console refresh in this pass: Google Play Closed testing - Alpha is still `Inactive` on version 5 (1.0.0); email lists `list` (1 tester) and `list2` (12 testers) remain unselected. Codemagic run `6ad426b77550aed8108fb98a` is marked post-processing failed, and the current Codemagic account says it cannot start builds. App Store Connect remains signed out. No tester list or store release setting was changed.
- Access recheck: both Firebase Authentication and Firestore Console routes deny the known PlayUp Google accounts, and `firebase projects:list --json` reports that the CLI is unauthenticated. I did not switch into other people's browser accounts or change project IAM. The five approved test targets therefore remain absent per the latest successful readback, but a fresh count is still blocked.

## Google Play tester assignment refresh — 18 October 2026

- Confirmed and saved the existing `list2` email list (12 testers) for Closed testing - Alpha, version 5 (1.0.0). Play Console now labels the track **Active** and lists `list2` as the selected tester list.
- Publishing overview shows this as a pending change: `Testers — Set testers to be managed by email lists: list2`. `Submit 1 change for review` is disabled, so the change is saved but not submitted; no notification or review submission is confirmed.
- This improves closed-test access but does not resolve the separate Google Play production-access gate. Production launch readiness remains conditional on account eligibility, live Firebase access and cleanup verification, legal/operator and password-reset configuration, App Check and signed-in booking validation, and the Apple/Codemagic release blockers recorded above.

## Firebase CLI access recheck — 18 October 2026

- The configured Firebase alias resolves to `sports-app-257a0`. A fresh CLI check was attempted with `firebase --version`, `firebase login:list`, and `firebase projects:list --json`; the executable produced no output within the timeout, including for `--version`, so this session could not obtain a fresh project/auth readback.
- The latest successful exact-target Firebase readback earlier on 18 October is recorded above: all five specifically approved test Auth/profile targets were already absent, and the remaining anonymous sessions, real public profiles, and Store Reviewer record were preserved. No new deletion was necessary or performed in this recheck.

### Fresh Firebase production readback after CLI sign-in — 18 October 2026

- Authenticated CLI as `tar20200202@std.psut.edu.jo`; project access verified for `sports-app-257a0`. Auth export returned 35 accounts: 30 anonymous and 5 named/provider accounts. The live export had no `test`, `dummy`, `fake`, `Guest Player`, or `player2@playup.com` label match. The temporary export was removed after summarizing.
- Firestore root collection listing returned only `academies`, `courts`, `platformConfig`, `publicProfiles`, and `users`. Current counts: 1 academy, 5 courts, 3 public profiles, and 5 user documents. No root `matches` or `leaderboards` collections exist. User records report 0 matches and 0 XP; no `isTest` flags are set. The separate Store Reviewer account remains; it is outside the approved deletion set.
- No deletion was warranted in this pass: there are no currently identifiable dummy accounts or match/leaderboard records. The 30 anonymous Auth sessions are not labeled and do not appear in the live users/publicProfiles collections; they were preserved because anonymous status alone does not establish that an account is test data. The exact five previously approved targets were already recorded absent by the earlier same-day exact-UID readback.

## Release actions completed — 18 October 2026 (CLI-authenticated pass)

- Firebase CLI is authenticated as `tar20200202@std.psut.edu.jo`; project `sports-app-257a0` is accessible. Fresh Auth export and Firestore readback found no test/dummy records matching the cleanup criteria. No further deletion was justified. Thirty unmatched anonymous Auth sessions were preserved because they are not tied to identified dummy profiles.
- Google Play Closed testing Alpha version 5 with tester list `list2` (12 testers) was submitted for review. Console now shows `Changes in review`; 0 testers have opted in so far. After approval, the 12 testers must opt in and remain opted in for 14 continuous days before production access application is available.
- Built Android release AAB version 1.0.0+6 with R8 optimization and resource shrinking. Release signing certificate matches the configured Play upload certificate. Runtime smoke on the API 36 emulator reached the sign-in screen with no observed R8 class-loading crash. AAB and R8 mapping are under `release/android-1.0.0-6-r8/`; the AAB has not been uploaded to Play.
- Admin production audit reports support email configured, but password-reset delivery and legal operator details missing. `admin-web` production environment does not contain `VITE_FIREBASE_APP_CHECK_KEY`; the admin client is fail-closed until that key is configured. Firebase App Check provider registrations exist for Android, iOS, and web, while Play Console still reports no Play Integrity integrated services.
- iOS build 25 uploaded and processed in App Store Connect, but Codemagic post-processing failed assigning the `testing` beta group. App Store Connect is signed out in the available Brave tab. `codemagic.yaml` no longer requests automatic beta-group assignment so a rerun can complete upload without that failure; a signed-in owner must manually add the processed build to TestFlight and complete any required App Store Connect settings.
- Remaining release gates: upload/review the new Android AAB, have 12 testers opt in for 14 days, complete legal operator/privacy and password-reset setup, configure the admin App Check site key, finish App Store Connect manual TestFlight assignment, and run signed-in production booking plus physical-device acceptance. Infinity court booking stays contact-only until rates and availability are confirmed.
