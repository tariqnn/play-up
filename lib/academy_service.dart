import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AcademyService {
  AcademyService._();
  static final instance = AcademyService._();
  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'me-central1');

  Future<String> academyId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in is required.');
    final profile = (await _db.collection('users').doc(uid).get()).data();
    final id = profile?['academyId'] as String?;
    if (id == null || id.isEmpty) {
      throw StateError('No academy is assigned to this account.');
    }
    return id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> courts(String academyId) => _db
      .collection('courts')
      .where('academyId', isEqualTo: academyId)
      .orderBy('name')
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> bookings(String academyId) => _db
      .collection('bookings')
      .where('academyId', isEqualTo: academyId)
      .orderBy('startUtc', descending: true)
      .limit(200)
      .snapshots();

  Future<void> saveCourt({
    String? courtId,
    required String name,
    required String sport,
    required int basePriceMinor,
    int openingHour = 6,
    int closingHour = 23,
  }) async {
    final tenantId = await academyId();
    final ref = courtId == null
        ? _db.collection('courts').doc()
        : _db.collection('courts').doc(courtId);
    await ref.set({
      'academyId': tenantId,
      'name': name.trim(),
      'sport': sport.trim(),
      'basePriceMinor': basePriceMinor,
      'currency': 'AED',
      'openingHour': openingHour,
      'closingHour': closingHour,
      'active': true,
      'blockedPeriods': <Map<String, dynamic>>[],
      'maintenancePeriods': <Map<String, dynamic>>[],
      'updatedAt': FieldValue.serverTimestamp(),
      if (courtId == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> transitionBooking(String bookingId, String status) async {
    await _functions.httpsCallable('transitionBooking').call({
      'bookingId': bookingId,
      'status': status,
    });
  }
}
