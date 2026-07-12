# Known deployment constraints

- The configured UAT payment method is **pay at venue**; the UI does not claim or store card payments. Adding online payment/refunds later requires a selected payment-provider account and webhook secrets.
- SMS/email channels remain disabled until provider credentials are supplied. In-app booking and matchmaking notifications are implemented.
- iOS compilation and signing must be performed on macOS with the target Apple Developer team. All required iOS AppIcon assets are generated from `icnos of app.jpeg`.
- Firebase Functions, rules, and indexes must be deployed to the chosen UAT project before device testing. No production deployment or production data mutation was performed.

No critical or high-severity application defect is known after the automated release gates.
