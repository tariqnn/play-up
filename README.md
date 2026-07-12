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
flutter build web --release
```

Privileged roles must be assigned by a trusted Firebase Admin SDK process or directly in the UAT console; clients cannot promote themselves. See `UAT_HANDOVER.md`.
