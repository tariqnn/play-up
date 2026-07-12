# PlayUp

Flutter/Firebase sports discovery, booking, academy, matchmaking, rewards, player, platform-admin and academy-admin application.

## Prerequisites

- Flutter SDK compatible with Dart 3.11+
- Firebase CLI (for rules/index deployment and emulators)
- A non-production Firebase project with Email/Password and desired social providers enabled

## Setup

```powershell
flutter pub get
flutterfire configure --project <uat-project-id>
firebase use <uat-project-id>
flutter analyze
flutter test
flutter run -d chrome
```

Deploy database configuration only after reviewing the selected project:

```powershell
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only functions,firestore:rules,firestore:indexes
flutter build web --release
flutter build apk --debug
```

Seed an isolated project whose ID contains `uat` using Application Default Credentials:

```powershell
$env:ALLOW_UAT_SEED='yes'
$env:FIREBASE_PROJECT_ID='<your-uat-project-id>'
$env:UAT_TEMPORARY_PASSWORD='<unique-12+-character-temporary-password>'
npm --prefix functions run seed:uat
```

Clients cannot promote themselves. See `UAT_HANDOVER.md`.
