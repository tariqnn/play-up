# Admin panel guide

Assign `role: superAdmin` through trusted UAT administration, sign in, open Settings, then Admin Panel. The hub manages courts, academies, offers, events and players. Custom dashboard supports drag reordering, compact/expanded sizing, hiding, adding, resetting and explicit save. Layouts persist in `dashboardLayouts/{uid}`.

Limited administrators use `role: platformAdmin` plus explicit permissions defined in `lib/access_control.dart`. Firestore remains authoritative if a UI entry is manipulated.
