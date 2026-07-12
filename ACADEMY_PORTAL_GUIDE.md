# Academy portal guide

Academy owners/staff require an immutable `academyId`. Settings exposes Academy Mode only for those roles. The portal contains dashboard customization, court, booking/check-in, offer, event and analytics entry points. Firestore permits academy writes only when the record's `academyId` matches the authenticated profile.

Academy staff receive only required `academy.*` permissions. Never pass an academy ID from UI directly into an unscoped query.
