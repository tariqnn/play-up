# UAT handover

Use an isolated Firebase UAT project. Create Auth users in Firebase, then assign profile documents using trusted Admin SDK/console. UAT-only suggested accounts: `superadmin@uat.invalid`, `bookingadmin@uat.invalid`, `owner-a@uat.invalid`, `owner-b@uat.invalid`, `staff-a@uat.invalid`, `staff-b@uat.invalid`, and player accounts. Use unique generated passwords communicated outside Git.

Required profile fields: `uid`, `displayName`, `role`, `permissions`, `suspended`; academy roles also require `academyId`. Create at least academies `uat-academy-a` and `uat-academy-b`, with courts carrying the same `academyId`. Do not reuse UAT credentials in production.

Payments/refunds, SMS/email delivery and server-generated notifications are not integrated because the repository contains no payment provider, mail/SMS account, Cloud Functions backend, or business credentials.
