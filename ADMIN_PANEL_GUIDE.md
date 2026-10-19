# Admin website guide

The platform administration surface is a dedicated React + TypeScript website in `admin-web/`; it is not rendered by Flutter. It provides a desktop sidebar, responsive mobile drawer, live dashboard totals, searchable tables, role-gated sign-in, create/edit/delete forms, and audited booking confirmation, cancellation and cash-collection actions. Modules cover academies, courts, bookings, users, matchmaking, reviews, audit logs and settings.

Run it with `npm --prefix admin-web install` and `npm --prefix admin-web run dev`. Build with `npm --prefix admin-web run build`. Deploy independently with `firebase deploy --config firebase.admin.json --only hosting` after selecting the intended admin Hosting site.

Assign `role: superAdmin` through trusted project administration, then sign in at the admin website. Firestore remains authoritative and rejects unauthorized or cross-tenant access even if the website is manipulated.

Production no longer exposes UAT data-seeding or UAT-user-creation callables. The guarded `functions/scripts/seed-uat.js` workflow remains available for an isolated UAT Firebase project or local Firebase emulators only.

Limited administrators use `role: platformAdmin` plus explicit permissions defined in `lib/access_control.dart`. Firestore remains authoritative if a UI entry is manipulated.
