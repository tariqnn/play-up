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

## Production goal refresh — 18 October 2026

- The goal is active. Google Play Publishing overview currently shows Closed testing - Alpha and PlayUp Android test build 6 under review while automated checks run. The AAB is uploaded. The tester email list has 13 addresses after adding the requested friend; that does not confirm opt-in. At least 12 must join and remain continuously opted in for 14 days before applying for production access.
- Codemagic build 26 is finished for iOS version 1.0.0 build 26 and its IPA upload to App Store Connect succeeded. The current browser is signed out of App Store Connect; Apple processing and TestFlight group assignment have not been verified.
- Fresh `vercel env ls production` shows support email and database configuration, but no Resend/SMTP sender variables, `NEXT_PUBLIC_OPERATOR_NAME`, or `NEXT_PUBLIC_OPERATOR_ADDRESS`; no admin Vercel App Check key is configured. The production audit itself could not be rerun because this Vercel CLI invocation did not pass a command to `env run`.
- Public DNS for `play-up.fit` currently resolves to Namecheap forwarding MX records and `v=spf1 include:spf.efwd.registrar-servers.com ~all`; `_dmarc.play-up.fit` returned no TXT record. This confirms inbound forwarding configuration only, not an authenticated PlayUp outbound sender. No provider-specific DKIM record was verified.
- The website reset-email template now sends branded HTML plus plain text, escapes links in HTML, and sets the published support address as Reply-To. Added template tests pass. `npm test` passes 14/14, `npm run typecheck` passes, and `npm run build` passes. ESLint did not finish in this environment, so lint is unverified.
- Firebase CLI is authenticated as `tar20200202@std.psut.edu.jo` and lists `sports-app-257a0`. Firebase Console in Brave is signed in as `info@creativenetworkservices.com` and reports that account cannot access the project; Firebase Auth email templates/custom domain therefore remain unverified.
- Follow-up after the prior Play read: automated checks completed successfully; Publishing overview now says the Android changes are in review. Build 6 is not yet approved or confirmed available to testers.
- Fresh Firebase CLI app listing confirms active PlayUp Android (`com.playup.playup`), production iOS (`com.playup.playu`), legacy iOS (`com.playup.playup`), and web apps. This only confirms registrations; it does not verify App Check enforcement or email templates.
- The remaining production gates are: configure and authenticate a transactional sender and validate real Gmail/Outlook delivery; configure Firebase Auth email templates/domain; enter accurate legal operator name/address; configure the admin App Check site key and verify server enforcement; confirm App Store Connect processing and add build 26 to the internal TestFlight group; complete signed-in production and physical-device acceptance. Court bookings remain intentionally contact-only until real prices and schedules are confirmed.
- Age-safety audit: the store audience was previously set to all ages, but no date-of-birth gate, verified guardian approval, or parental chat controls were found in the Flutter account/profile flow. The privacy and terms drafts still contain unresolved minimum-age/legal-review placeholders. Do not claim an all-ages launch is ready until this is addressed; choose an adult-only release with matching store settings and enforcement, or implement and test a compliant child/guardian flow with legal review.
- Transactional email follow-up: the website password-reset template is now branded HTML plus plain text with Reply-To, but production has no authenticated outbound provider configured. `palyo-site/docs/EMAIL_DELIVERABILITY.md` records the DNS/provider setup. Inbox placement cannot be guaranteed and has not been tested; verify SPF, DKIM, DMARC alignment and real Gmail/Outlook headers after the sender is configured.

## Release/email verification refresh — 18 October 2026

- Website email-template change was committed and pushed to `tariqnn/palyo` as `e56a05f` (`Improve PlayUp password reset email`). Vercel production deployment `dpl_Ayh9GG1QPKY9FmoMtjp6cX1mQVi1` reached `READY` and owns `play-up.fit` / `www.play-up.fit`. `/forgot-password` and `/api/health` both returned HTTP 200.
- The production reset sender is still unconfigured: current Vercel Production variables contain no `RESEND_API_KEY`, `EMAIL_FROM`, or SMTP sender credentials. The handler intentionally fails closed when a reset is requested without a provider, so a real website reset message will not be delivered yet. No Gmail/Outlook inbox test was performed.
- Current Play Console page still shows Android test build 6 under “Changes in review.” This is not approved and no 14-day tester opt-in period is established.
- Current App Store Connect Apps list shows PlayUp iOS 1.0 as “Prepare for Submission.” Codemagic confirms build 26 uploaded successfully, but the current Apple state does not show a submitted review or TestFlight-ready assignment. TestFlight group and processed build remain unverified.

### Apple TestFlight live follow-up — 18 October 2026

- App Store Connect TestFlight shows build 1.0.0 (26) with status **Testing**, assigned to internal group `testing` (1 tester). The tester account installed build 26 on an iPhone 17 Pro running iOS 27.0 and has 66 sessions. This verifies a real internal TestFlight installation.
- The App Store version record remains **Prepare for Submission** and still references build 14, not build 26. Build 26 is available to the internal tester, but is not the selected App Store review build. The App Store Connect version page controls for changing the build did not respond in the browser session; no version change or review submission was made.
- Google Play Publishing overview still shows build 6 under **Changes in review**. It is not yet approved for the closed test.

### Current session refresh � 18 October 2026

- App Store Connect TestFlight build 1.0.0 (26) is assigned to internal group `testing` (1 tester). The �What to Test� instructions were saved and the page showed **Saved** on readback. The notes direct testers to check venue discovery, court photos, map/directions, contact-only booking, matches, chat, profiles, and leaderboard; no online payments are represented.
- Website password reset is still not deliverable: Vercel production has no authenticated transactional sender credentials, and the live handler fails closed until configured. DNS presently has Namecheap forwarding/SPF only; outbound provider DKIM and DMARC alignment plus real inbox delivery have not been established or tested. Firebase mobile reset-email configuration remains unverified.
- Google Play Integrity remains unlinked. Play Console requires acceptance of its Terms of Service and linking `com.playup.playup` to `sports-app-257a0`; that agreement was presented but not accepted in this session.
- Production publication is not ready: Android build 6 remains under review; the App Store version remains Prepare for Submission and still selects build 14. Build 26 is internal TestFlight only. The production gate list above remains open.

### Verification pass � 18 October 2026 (current workspace)

- Flutter: `flutter analyze --no-pub` passed with no issues; `flutter test --no-pub` passed 34/34.
- Firebase Functions domain tests: `npm test` passed 9/9, including exclusion of guest/demo/test profiles from public profiles.
- Firestore rules emulator tests: 13/13 passed against the current `firestore.rules`. The emulator logged a test project ID mismatch (`demo-playup` emulator vs. `playup-rules-test` tests); the assertions still passed, but the harness should be normalized before relying on clean emulator logs.
- Website: `npm test` passed 14/14, `npm run typecheck` passed, and `npm run build` passed. Fresh live `curl` checks returned HTTP 200 for `https://play-up.fit/api/health` and `/forgot-password`.
- Fresh production Vercel environment-variable listing still has no `RESEND_API_KEY`, `EMAIL_FROM`, SMTP sender credentials, operator name/address, or admin App Check key. DNS resolves only the Namecheap forwarding SPF TXT at the apex; `_dmarc.play-up.fit` has no TXT answer. Consequently site reset delivery, mobile Firebase reset email, legal operator disclosure, and admin App Check setup remain unverified or incomplete.
- Google Play Integrity is still unlinked; its Terms of Service and link-project controls remain on screen awaiting explicit approval. No release state changed.
- The current App Store Connect submission page did not render the version form after navigation; build 26 remains verified only in internal TestFlight as Testing, with saved test instructions. The store version submission is not verified as updated from build 14.

### Latest live verification — 18 October 2026

- Android Closed testing Alpha is **Active** with “PlayUp Android test build 6,” released on 18 October and available to selected testers. The selected email list `list2` contains 13 addresses, including the requested friend. This confirms access is configured; it does not prove any tester has opted in or completed the 14-day continuous test period required before applying for production access.
- Play Integrity is still not linked. I accepted the Play Integrity terms after the user’s explicit approval and entered the verified Cloud project number `634238605050` (`sports-app-257a0`); Play Console still has no selectable project and its Link project button remains disabled.
- After the user approved the separate Google Cloud Platform Terms, the open Cloud Console moved past its welcome screen but returned **You need additional access** for `sports-app-257a0`. The current browser account therefore cannot administer this project. The project must be opened by a direct Google Cloud project Owner, or that Owner must explicitly grant the current account the necessary role, before linking Play Integrity. No IAM access was changed.
- Fresh Firestore rules suite result: 13/13 passed after starting the Firestore emulator separately and setting `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080` and `GCLOUD_PROJECT=demo-playup`. The Firebase CLI wrapper itself failed to pass stdin/arguments to the test child process; the direct emulator plus test process passed. The emulator has been stopped.
- Resend’s current free plan is $0/month for up to 3,000 emails/month, capped at 100/day. No paid plan is needed for normal password-reset volume. Production website email still needs the user to create/verify a Resend account/domain and add the API key securely to Vercel; Firebase Auth mobile reset email remains a separate unverified sender path. Do not claim inbox placement until real Gmail/Outlook delivery and SPF/DKIM/DMARC headers are checked.
- Correction to the Play Integrity bullet immediately above: the user approved the Play Integrity Terms, but Play Console did not accept them because no Cloud project could be selected and the Link project button stayed disabled. The separate Google Cloud Platform Terms were accepted in the browser; the resulting page identifies the missing permission as `resourcemanager.projects.get` for `sports-app-257a0`.
### Play Integrity IAM handoff — 18 October 2026

- The Firebase CLI’s signed-in account `tar20200202@std.psut.edu.jo` is a project Owner on `sports-app-257a0`; this was verified from the project IAM policy. The user explicitly authorized granting Project Owner to `info@creativenetworkservices.com`.
- The Cloud Resource Manager IAM API rejected a direct Owner binding with `ORG_MUST_INVITE_EXTERNAL_OWNERS`. Google requires the external-owner invitation flow in Cloud Console; the CLI/API cannot bypass it. A Cloud Console session for the existing Owner account is open at Google’s “Verify it’s you” password prompt and has been marked for handoff. I did not enter credentials or send an invitation.
- After the Owner account is re-verified, use Cloud Console to invite `info@creativenetworkservices.com` as project Owner. That account must accept Google’s project invitation. Then retry the Play Integrity link and verify the linked project readback. No role was added, no invitation was sent, and Play Integrity remains unlinked.
### Mobile app Firebase Auth email audit — 18 October 2026

- The Flutter app uses Firebase Auth directly for password resets (`sendPasswordResetEmail`), account verification (`sendEmailVerification`), and academy staff setup emails. These messages are sent by Firebase Auth, not by the website and not through Resend/SMTP credentials.
- Read-only Firebase Auth project configuration for `sports-app-257a0` shows email/password sign-in enabled, sender method `DEFAULT` (Firebase/Google sender), `noreply` sender local part, default reset and verification subjects, and Firebase's hosted action callback at `https://sports-app-257a0.firebaseapp.com/__/auth/action`. No custom sender domain is configured (`useCustomDomain=false`).
- The native SDK calls and default hosted action handler are in place. The code does not supply a mobile deep-link continuation for reset/verification, so the user completes the action in Firebase's hosted browser flow and returns to the app manually. This is a functional baseline, but app return/deep-link behavior has not been validated on physical iOS and Android devices.
- Hardened the reset flow so `user-not-found` and `user-disabled` return the same generic “if an account exists” confirmation as a successful request; sign-in errors also no longer name a missing account. This avoids disclosing whether an email is registered.
- Remaining mobile email acceptance: configure PlayUp display name and support reply-to in Firebase Auth templates; if branded sending links are required, configure Firebase's custom email domain, publish only the exact DNS records Firebase provides, and apply the domain after verification. Then send reset and verification emails to controlled test inboxes and check delivery/headers, open the links on supported iOS/Android devices, complete the actions, and confirm the account state updates in the app. Inbox placement is not guaranteed until those real inbox checks pass.
- No reset or verification email was sent to a real person during this audit. The Firebase auth settings were read only; the template and domain have not been changed.
### Mobile app follow-up — 18 October 2026

- `dart analyze lib/main.dart lib/more_screens3.dart` completed successfully: no issues found. `flutter test --no-pub` passed all 34 tests.
- A targeted Identity Toolkit config update to customize the reset and verification templates was rejected with HTTP 400 `EMAIL_TEMPLATE_UPDATE_NOT_ALLOWED`; readback confirms no template changes were saved. Firebase still uses its default subjects/body, `noreply` reply-to, default sender, and default Firebase-hosted action callback. The REST API write was not retried through an alternate path.
- No live password-reset/verification email was sent. The final delivery and link-completion check needs an inbox controlled by the owner/tester plus an iOS and Android device. The mobile app UI code is changed locally but no new signed store build has been produced from this change.### Mobile reset-email delivery test � 18 October 2026

- Firebase Auth confirmed the supplied Outlook address is a registered PlayUp account and accepted one password-reset email request. The tester reports the message arrived in Junk, so mobile reset delivery is proven but inbox placement failed.
- The mobile sender remains Firebase Auth's default Google sender; the website's Resend configuration is a separate path and does not affect mobile Auth emails. Do not report email as inbox-ready.
- To improve mobile deliverability, move Auth email sending to a verified PlayUp sending domain with authenticated SPF/DKIM (and aligned DMARC), and use a reputable SMTP provider. This requires a verified sending domain, provider SMTP credentials, and the project/account capability to configure custom SMTP (Identity Platform). Retest Outlook and Gmail, inspect headers, and validate the reset action on both platforms. Inbox placement cannot be guaranteed by configuration alone.
- Follow-up: Firebase Console is now accessible in Brave as project owner `tar20200202@std.psut.edu.jo`. Password-reset template editing in the console is also blocked with �Email template updates are currently unavailable for this project�; no branded-template changes were saved. The console does expose SMTP settings, but no provider credentials are configured.
- Firebase generated custom sender-domain records for `play-up.fit`: TXT `firebase=sports-app-257a0`; CNAME `firebase1._domainkey` ? `mail-play--up-fit.dkim1._domainkey.firebasemail.com.`; CNAME `firebase2._domainkey` ? `mail-play--up-fit.dkim2._domainkey.firebasemail.com.`. It also requests SPF `v=spf1 include:_spf.firebasemail.com ~all`. Existing DNS has Namecheap forwarding SPF `v=spf1 include:spf.efwd.registrar-servers.com ~all`; preserve forwarding by combining both includes in the existing single SPF TXT record rather than adding a second SPF record. DNS has not yet been changed; Firebase template edit is blocked, so contact Firebase Support or enable custom SMTP through project settings before relying on these records.
- Android version 1.0.0 build 7 AAB built successfully (63 MB) locally. Play Console closed-test release draft `PlayUp Android test build 7` is saved with notes, but still has no uploaded AAB; current CUA upload workflow cannot attach the local file. Closed testing remains on build 6 with `list2` (13 testers).
- iOS Codemagic build #27 completed from commit `7b83aa4`; App Store Connect upload succeeded (delivery UUID `ffa1155b-15d4-453f-8670-2f5143b19d23`). Current App Store Connect readback shows Build 27 Internal, status Testing, assigned to internal group `testing`.

### Firebase Auth sender-domain update — 18 October 2026

- To preserve the existing root-domain Namecheap Email Forwarding SPF, configured Firebase Auth on the isolated sender subdomain `mail.play-up.fit`.
- Added and read back from Namecheap: TXT `mail` = `v=spf1 include:_spf.firebasemail.com ~all`; TXT `mail` = `firebase=sports-app-257a0`; CNAME `firebase1._domainkey.mail` -> `mail-mail-play--up-fit.dkim1._domainkey.firebasemail.com.`; CNAME `firebase2._domainkey.mail` -> `mail-mail-play--up-fit.dkim2._domainkey.firebasemail.com.`. Queried the Namecheap authoritative DNS servers and confirmed all records resolve.
- Firebase Console returned “Verification complete”; applied the custom domain. Password-reset preview now shows `noreply@mail.play-up.fit`. Existing Vercel A/CNAME, root Email Forwarding MX/SPF, and mail setting were left intact. Additional root-domain Firebase verification/DKIM records from the initial root-domain attempt remain in DNS; they are non-conflicting but unused by the configured `mail.play-up.fit` sender.
- Sent one fresh password-reset test from Firebase Console to the user-designated Outlook test account. Firebase accepted the send; inbox vs Junk placement and message headers await the account owner’s check. Inbox placement is not yet verified or guaranteed.
- Firebase still blocks edits to sender display name, reply-to, subject, and body with “Email template updates are currently unavailable for this project.”

### Firebase reset email branding follow-up — 18 October 2026

- Updated Firebase project Public-facing name from `project-634238605050` to `PlayUp`; verified the project settings read back as `PlayUp`. A fresh password-reset message then used subject `Reset your password for PlayUp` and body text referred to the `PlayUp` account/team, removing the numeric project label.
- The new message was delivered from `noreply@mail.play-up.fit` but Outlook again placed it in Junk. The downloaded message headers showed SPF `pass`; this check did not establish DKIM or DMARC results. No inbox placement claim is warranted.
- Prepared a PlayUp-branded HTML template with a wordmark treatment, support link, and reset button in Firebase’s editor. Firebase refused the save and returned: `Email template updates are currently unavailable for this project.` Read-back confirmed the sender name, Reply-to, subject, and body stayed at Firebase defaults. Therefore no custom HTML or logo is active.
- Firebase SMTP settings are available but disabled, and fields require a configured provider. No SMTP/Resend credentials were found in the local site env file. A real provider account/credentials plus Firebase’s ability to enable custom SMTP (or Firebase Support lifting the template restriction) are still required for a branded mobile reset email. The current website email sender is a separate pathway.

### Android 7 and current store submission gate — 18 October 2026

- The current source declared `version: 1.0.0+6` while Play Console already had version code 6 active. Bumped only `pubspec.yaml` to `1.0.0+7`, built `flutter build appbundle --release` successfully, and verified the merged release manifest reports `versionCode="7"` / `versionName="1.0.0"`. The AAB is `build/app/outputs/bundle/release/app-release.aab` (66,030,932 bytes); its `META-INF/PLAYUP-R.RSA` signature entry is present.
- Committed and pushed the version bump as `96b8beb` to `uat-admin-platform-readiness`; no other dirty files were staged. Codemagic's current build list still ends at build #27 from `7b83aa4`; build start controls report insufficient permission, and no build for the pushed commit appeared on readback.
- Play Console Closed testing Alpha still has active version code 6. Draft release `PlayUp Android test build 7` has no attached bundle. The bundle library offers only codes 5, 4, and 2, so the freshly built code 7 AAB has not been uploaded or released. The Play Console Upload button did not open a file picker through the available browser control.
- App Store Connect iOS 1.0 remains `Prepare for Submission` and selects build 14 (1.0.0). The iPhone screenshot panel shows `0 of 10 App Screenshots` and `0 of 3 App Previews`; no video preview is needed, but screenshots remain a release gate. Codemagic still shows only build #27 (from `7b83aa4`) and starting builds is disabled for this account.

## Production-readiness refresh — 18 October 2026 (current checkout)

### Verified this turn
- The home carousel's first three cards point to the three Infinity Sports court images (padel, indoor basketball, 3x3). A fresh Android release AAB was built from this checkout as `1.0.0+8` (version code 8), archived at `release/android-1.0.0-8/playup-1.0.0-8.aab`, and accompanied by `mapping.txt` and `SHA256SUMS.txt`. All three assets are present in the bundle. Its signing certificate fingerprint matches the previously accepted PlayUp upload bundle. `flutter analyze --no-pub` reports no issues and `flutter test --no-pub` passes 34/34.
- Functions `sendPlayUpPasswordReset` and `sendPlayUpEmailVerification` are deployed in `me-central1` on Node 22. The functions require App Check; the Flutter release startup activates Play Integrity on Android and App Attest/DeviceCheck fallback on iOS. Functions TypeScript build and 9/9 domain tests pass; production dependency audit reports zero vulnerabilities. Device-side App Check and reset-link completion remain unverified.
- Website commit `0db11cc` is deployed to production as Vercel deployment `dpl_9yTqrRah8k4JtoTjVsWPVZv3FSSq` (READY; aliases include `play-up.fit`). The updated high-contrast email logo returns HTTP 200 as `image/png` (5,645 bytes). This verifies the asset, not post-change inbox placement.
- The live website production audit connects to its database and reports 7 venues, 1 academy, no demo venues, no future games, and 0 real accounts. It reports `resetEmailConfigured: false` and `legalOperatorConfigured: false`.
- Admin production build succeeds, but the current admin runtime has only `.env.example` and `.env.local`; no production Firebase/App Check values were verified. The app intentionally fails closed when production App Check configuration is absent.
- Current computer/browser bridge reports no available browser or Chrome bridge socket. No Android device or emulator is attached (`flutter devices` lists only Windows, Chrome, and Edge). Google Play and App Store Console release state therefore cannot be refreshed or changed from this session.

### Remaining launch gates
- Upload AAB version code 8 to the Google Play closed-test release and confirm processing and tester access. The last verified Play Console record is closed-test build 6 with 13 emails assigned; this does not establish opt-in or the continuous 14-day test period. Play Integrity remains unlinked due missing Cloud project access.
- Refresh App Store Connect: the latest saved record says iOS build 27 was assigned to internal testing, while a separate older submission panel had no screenshots. Current processing, required screenshots, review metadata, and group availability must be verified in App Store Connect.
- Test on real iOS and Android devices, including signup, reset and verification email links, App Check, location/maps, booking/contact-only court flow, chat/social safeguards, push, account deletion, accessibility, and offline/error handling.
- Resolve the audience policy before store release. The app has social profiles and chat but no date-of-birth gate, verified parent approval, or parental controls. The all-ages store audience previously selected is not supported by those safeguards. The Terms draft still leaves eligibility and cancellation policy unresolved; both legal drafts require accurate operator identity and qualified review.
- Supply the registered legal operator name and address and finalize/publish counsel-reviewed Terms and Privacy Policy. Current live audit confirms operator details are absent.
- Configure a website transactional email provider in Vercel Production; the website reset route remains unconfigured even though the mobile Firebase callable uses Resend. Then test website reset and mobile reset separately in controlled Gmail and Outlook inboxes and inspect SPF/DKIM/DMARC results. No inbox placement guarantee is established.
- Configure production Firebase/App Check settings for the admin deployment, verify valid tokens and enforcement, and complete signed-in admin acceptance. The production admin configuration is not verified.
- Complete operational readiness: confirmed venue rates/availability or keep the current contact-only presentation; support and incident-response ownership; backup/restore drill; final store screenshots and listing answers; and a production rollback plan.

### Release and reset-email log follow-up — 18 October 2026

- GitHub check-runs for current mobile HEAD `48d9495e5bd652387e4a6025460ebb5f9093c01a` show `PlayUp iOS - TestFlight` completed successfully on Codemagic build `6ad506f77550aed8108fe5d7` at 17:58 UTC. App Store Connect processing, compliance status, screenshot completeness, and internal-group assignment still require a live ASC readback.
- Recent Cloud Logging records for `sendPlayUpPasswordReset` show App Check verification passed on requests. Two earlier calls reached Resend but were rejected with HTTP 422. Current deployed function uses Secret Manager key version 3 after the replacement. The logs do not expose Resend's validation reason, and no successful post-replacement reset delivery/link completion was verified in this turn. Re-test from a production build and inspect provider logs plus the controlled inbox before calling mobile reset ready.

## 2026-10-18 Android follow-up
- Updated Explore court ordering so the three verified Infinity court listings (3x3, 5x5, Padel) appear before other venues regardless of location distance. The multipurpose hall has no verified photo and no longer pushes the padel court out of the first three.
- Bumped Android version to `1.0.0+9` (versionCode 9). `flutter analyze --no-pub` is clean and `flutter test --no-pub` passes 34/34.
- Built signed AAB and APK at `release/android-1.0.0-9/`. APK reports package `com.playup.playup`, versionCode 9, and signing certificate SHA-256 `44f34e131d65f8dd80a2c49c808a872596dce99a12e8a039154068b7fc6b5519` (matches the previously accepted upload certificate). AAB/APK SHA-256 values are recorded in `SHA256SUMS.txt`.
- Installed version 9 on the Android API 36 Pixel emulator. The Explore list displayed Infinity 3x3, Infinity 5x5, and Padel Court by Merry Sports with their corresponding real court photos as the first three listings; app remained open and filtered logs showed no fatal Flutter/Android exception.
- The friend�s Google Play test download is still on the older published test release. Version 9 has not been uploaded or assigned in Play Console because this session has no connected browser/Play Console bridge. The existing closed-test opt-in link should serve version 9 after it is uploaded, saved, and the release becomes available to testers; no new link can be issued until that happens.

## 2026-10-18 release handoff update
- Play Console now shows Android closed-test release `PlayUp Android test build 9` under `Changes in review`. Automated quick checks completed and Google Play confirmed “Your changes are now in review.” It is not yet available to testers; the existing opt-in link remains the same and will deliver v9 only after Google completes review and the release becomes available.
- Codemagic completed iOS build 32 from `uat-admin-platform-readiness` commit `f8081ce330a190983bd69367762588904705f8ed`, version `1.0.0`, bundle `com.playup.playu`. The signed `playup.ipa` and artifact archive are present; the Publishing log says `UPLOAD SUCCEEDED` to App Store Connect. The ASC tab is signed out, so Apple processing and TestFlight group assignment are not verified.
- The first three Infinity Sports venue photos are included in that source commit; Android version 9 was already installed and visually checked on the Pixel API 36 emulator.

## 2026-10-18 iOS sports-photo correction
- Replaced the welcome carousel and the first three home sports carousel photos with local, generic football, basketball, and volleyball action images. Infinity Sports venue photos remain on the actual venue listings.
- Flutter analysis is clean and all 34 widget/unit tests pass. Commit `c1906dc` was pushed to `uat-admin-platform-readiness`.
- Codemagic build `6ad523547550aed8108feccf` checked out commit `c1906dc87b0bc4db2ea00495a5a8593df6cf97b4`, built iOS version `1.0.0` build `33`, and reports `UPLOAD SUCCEEDED` to App Store Connect (delivery UUID `163ed4d1-2cdf-465d-8a54-db38edfa986e`). Apple processing and TestFlight group availability remain unverified because App Store Connect is signed out in the connected browser.

## 2026-10-18 sports-photo release follow-up
- Android v10 (`versionCode 10`) was built, signed with the existing Play upload certificate, installed and launched on the API 36 emulator. Its Alpha closed-test release was submitted to Google Play; Publishing overview shows `Changes in review`. It is not downloadable by testers until Google finishes review. Existing closed-test opt-in URL remains `https://play.google.com/apps/testing/com.playup.playup`.
- iOS build 34 from commit `3da6685f99fa9a162c9e5d78f7a6a3a00c755621` passed Codemagic analysis/tests and uploaded to App Store Connect (delivery UUID `f74af56a-085d-4254-ad75-cb61d570a61c`). Apple processing completed, but Codemagic post-processing could not attach the build to the internal `testing` group. Build 34 must be added to that internal group in App Store Connect. The connected ASC tab is signed out.
- Removed the incompatible internal `beta_groups: testing` assignment from future Codemagic runs and pushed commit `46fdc25`; `submit_to_testflight: true` remains configured.

## 2026-10-19 release-readiness continuation

- Fixed the court directory and home court preview cards to use sport-action imagery by sport, while keeping venue photos on venue-detail pages. Commit `1618505` is on `origin/uat-admin-platform-readiness`. Codemagic build 36 passed its build/test steps, uploaded IPA build `1.0.0 (36)`, and Apple finished processing it. Live App Store Connect readback confirms build 36 is assigned to internal group `testing` (one tester). It is available to that internal group; no physical iPhone check has been performed. Codemagic's Beta App Review step could not submit build 36 because build 34 is already under Beta App Review.
- Built signed Android AAB `build/app/outputs/bundle/release/app-release.aab` for the Play test-track update using `--build-number=12`; file size is 72,043,546 bytes and SHA-256 is `08670F4A9D049DA5712F1AD641A594B42C8BA44AE5F096E6D8D4F4F2FEFFBF`. `jarsigner` verified the bundle signature and reported signer `CN=PlayUp, OU=Mobile, O=PlayUp, L=Amman, ST=Amman, C=JO`. Play Console still lists closed Alpha build 10 with `list2` (13 testers). A closed-test release draft named `PlayUp Android test build 12` is saved with notes, but the AAB is not attached or submitted. This session's Brave controller cannot attach the local file through the system picker; upload and release submission remain open.
- Live Firebase App Check readback shows Play Integrity registered for Android `com.playup.playup` and App Attest registered for the production iOS app `com.playup.playu`. The separate Firebase web app is not registered. Its console offers reCAPTCHA Enterprise/Fraud Defense, which requires a site key and is subject to Google Cloud terms; the legacy reCAPTCHA provider is marked deprecated. No registration or terms acceptance was made.
- The production Vercel `admin-web` environment has seven Firebase configuration variables but lacks `VITE_FIREBASE_APP_CHECK_KEY`; its production code fails closed without that key. The Firebase web app registration and the matching App Check key must be configured before the admin can run in production. Do not enable App Check enforcement until valid client tokens have been verified against the active mobile and web builds.
- The production `palyo-site` Vercel environment listing still has no `RESEND_API_KEY` or `EMAIL_FROM`; website reset-email delivery is separate from the mobile Firebase password-reset callable. The Vercel environment also lacks verified legal-operator identity/address values. Do not copy the mobile Resend credential into Vercel without explicit authorization for that destination.
- Still unverified for public release: a successful reset/verification email and completed action on current physical iOS/Android builds; inbox placement (Outlook previously put the Firebase message in Junk); registered legal operator identity and counsel-reviewed Terms/Privacy; child-safety audience decision and controls; Google Play test release availability after upload/review; current production website reset sender; admin App Check configuration; database backup/restore drill; final signed-in physical-device acceptance; and support/incident/rollback ownership. Court bookings remain contact-only until rates and availability are confirmed.

## 2026-10-19 follow-up verification

- Updated the mobile password-reset and verification email markup with a table-based PlayUp wordmark that does not depend on blocked remote images or CID attachments. `npm test` in `functions/` passes 11/11 tests. Firebase successfully deployed `sendPlayUpPasswordReset` and `sendPlayUpEmailVerification` to `sports-app-257a0`; provider delivery and inbox placement for a newly generated message have not been re-tested after this deployment.
- The website `/api/health` and `/forgot-password` routes return HTTP 200. This confirms route availability only. The current production Vercel environment list for `palyo-site` has no `RESEND_API_KEY`, `EMAIL_FROM`, or SMTP provider variables, so website reset delivery remains unconfigured. Do not copy the mobile Firebase secret into Vercel without explicit authorization for that destination.
- App Store Connect shows iOS `1.0.0 (36)` assigned to the internal `testing` group (one tester). The sport-specific listing-image fix is in that build; physical iPhone verification remains pending.
- Android release AAB version 12 is built and signature-verified, but the open Play Console closed-test draft has no version 12 bundle attached. The draft still lists version 10; build 12 has not been uploaded or submitted. Uploading requires selecting `build\\app\\outputs\\bundle\\release\\app-release.aab` in Play Console's native file chooser.
- Production launch remains blocked on the previously listed business/legal, admin App Check, Android track upload/review, real device, email inbox, and recovery/support checks; this follow-up does not close those gates.
- The read-only production audit returned database `ok`, 1 total user, 7 venues, 0 demo venues, 0 future games, 1 academy, 0 activities/offers/tournaments/community posts, 0 real accounts, `resetEmailConfigured: false`, `supportEmailConfigured: true`, and `legalOperatorConfigured: false`. The zero activity and user counts are production facts at the audit time, not a claim that those features were tested end to end.
- The current public Creative Networks contact section lists `info@creativnetworks.com`, `+962 795 550 073`, and `Amman, Jordan`. It does not show a full legal operator name or street address, so the store/legal operator fields cannot be completed from that page alone.
- Current checkout verification: `flutter analyze --no-pub` reported no issues, and `flutter test --no-pub` passed all 34 tests. These checks do not substitute for installed-build testing on the iPhone or Android device.
- Current checkout also passes the Firestore rules emulator suite (13/13) and `admin-web` production compilation (`tsc -b && vite build`). The admin build still remains unavailable in production until web App Check is configured; the compile result alone does not validate signed-in admin workflows.
