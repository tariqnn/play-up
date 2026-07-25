# Owner accounts and testing

PlayUp supports two separate owner scopes:

- **Academy owner** — manages the academy profile, staff, all academy courts,
  bookings, offers, events, tournaments, and analytics.
- **Court owner** — manages only the single court assigned to the account,
  that court's bookings, cash collection, and court analytics. Firestore rules
  and Cloud Functions enforce the boundary; it is not only a UI filter.

## Create an owner

1. Open the PlayUp Admin website and sign in as a super administrator, or as a
   platform administrator with `users.manage`.
2. Open **Owner Accounts**.
3. Choose **Academy owner** or **Court owner**.
4. Enter the owner's name and email.
5. Select the academy. For a court owner, also select the exact court.
6. Select **Create account and send email**.
7. The owner opens Firebase's password-setup email, chooses a password, and
   signs in to the PlayUp app.

Do not create owner records directly in Firestore. The callable function
creates Firebase Authentication and Firestore identity records together and
writes an audit log.

### Production prerequisite

The Firebase project must be on the Blaze plan before the owner-account and
booking callable functions can be deployed. After upgrading, deploy them with:

```powershell
firebase deploy --only functions --project sports-app-257a0
```

Until that deployment succeeds, use the Firebase emulators for owner-account
workflow testing; the production Admin button cannot create Authentication
users without the callable function.

## Test the roles

Use two different email addresses so each scope is unambiguous.

### Academy owner

1. Create an academy with two courts in Admin.
2. Create an academy-owner account for that academy.
3. Sign in to the app with the new account.
4. Confirm that **Academy Operations** shows academy profile, staff, both
   courts, all academy bookings, offers, events, tournaments, and analytics.
5. Edit one court and confirm the change appears in Admin.

### Court owner

1. Create a court-owner account assigned to only the first court.
2. Sign in to the app with that account.
3. Confirm that **Court Operations** shows the assigned court only.
4. Confirm that bookings and revenue include only the assigned court.
5. Confirm academy profile, staff, offers, events, and tournament management
   are not available.
6. Attempt direct access to the second court with the Firebase Rules test
   suite. The request must fail.

## Automated checks

Run:

```powershell
flutter test
npm --prefix functions test
npm --prefix admin-web run build
firebase emulators:exec --only firestore "npm --prefix rules-tests test"
```

The rules test includes an explicit court-owner isolation case.

## Release signing

Android release builds use `android/key.properties` and
`android/app/playup-release-keystore.jks`. Both are intentionally ignored by
Git. Back them up in a secure password manager or encrypted company vault.
Losing the signing key can prevent future upgrades to the same Android app.
