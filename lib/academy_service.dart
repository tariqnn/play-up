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

  Stream<DocumentSnapshot<Map<String, dynamic>>> academy(String academyId) =>
      _db.collection('academies').doc(academyId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> staff(String academyId) => _db
      .collection('users')
      .where('academyId', isEqualTo: academyId)
      .snapshots();

  Future<void> saveAcademy(Map<String, dynamic> values) async {
    final id = await academyId();
    await _db.collection('academies').doc(id).set({
      ...values,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> createStaff({
    required String displayName,
    required String email,
    required String temporaryPassword,
    required List<String> permissions,
  }) async {
    await _functions.httpsCallable('createAcademyStaff').call({
      'displayName': displayName,
      'email': email,
      'temporaryPassword': temporaryPassword,
      'permissions': permissions,
    });
  }

  Future<void> saveCourt({
    String? courtId,
    required String name,
    required String sport,
    required int basePriceMinor,
    required String currency,
    required String address,
    required double latitude,
    required double longitude,
    String imageUrl = '',
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
      'currency': currency,
      'address': address.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'imageUrl': imageUrl.trim(),
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

  Future<void> recordCashPayment(String bookingId) async {
    await _functions.httpsCallable('recordCashPayment').call({
      'bookingId': bookingId,
    });
  }
}
