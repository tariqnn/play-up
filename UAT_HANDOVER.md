# UAT handover

Use an isolated Firebase project whose ID contains `uat`. Run `npm --prefix functions run seed:uat` with `ALLOW_UAT_SEED=yes`, `FIREBASE_PROJECT_ID`, `UAT_TEMPORARY_PASSWORD`, and Application Default Credentials. The safety guard refuses non-emulator projects without `uat` in their ID. It creates the documented administrators, owners, staff, player, two academies and tenant-tagged courts. Share the temporary password outside Git and require replacement.

Required profile fields: `uid`, `displayName`, `role`, `permissions`, `suspended`; academy roles also require `academyId`. Create at least academies `uat-academy-a` and `uat-academy-b`, with courts carrying the same `academyId`. Do not reuse UAT credentials in production.

Bookings use pay-at-venue and do not collect card data. In-app notifications are server generated. SMS/email are optional deployment integrations and remain disabled without provider credentials.
