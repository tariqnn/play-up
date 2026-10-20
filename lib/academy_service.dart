import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

const _useFirebaseEmulators = bool.fromEnvironment('USE_FIREBASE_EMULATORS');

/// The staff Auth account and Firestore record were created successfully,
/// but the password-setup email failed to send. Callers should offer to
/// resend the reset email to [email] rather than creating the account again.
class StaffSetupEmailException implements Exception {
  StaffSetupEmailException(this.email, this.cause);

  final String email;
  final Object cause;

  @override
  String toString() =>
      'The staff account was created, but the setup email could not be sent. $cause';
}

class OwnerScope {
  const OwnerScope({
    required this.academyId,
    required this.role,
    required this.courtIds,
    required this.permissions,
  });

  final String academyId;
  final String role;
  final Set<String> courtIds;
  final Set<String> permissions;

  bool get isCourtOwner => role == 'courtOwner';
  bool get isAcademyOwner => role == 'academyOwner';
  bool get canManageAcademy =>
      isAcademyOwner || permissions.contains('academy.profile.manage');
  bool get canManageStaff => isAcademyOwner;
  bool get canManageCourts =>
      isAcademyOwner ||
      isCourtOwner ||
      permissions.contains('academy.courts.manage');
  bool get canManageBookings =>
      isAcademyOwner ||
      isCourtOwner ||
      permissions.contains('academy.bookings.manage') ||
      permissions.contains('academy.bookings.checkin');
  bool get canManageCatalog => isAcademyOwner;
  bool get canManageTournaments =>
      isAcademyOwner || permissions.contains('academy.tournaments.manage');
  bool get canViewAnalytics =>
      isAcademyOwner ||
      isCourtOwner ||
      permissions.contains('academy.reports.view');
  String? get assignedCourtId =>
      isCourtOwner && courtIds.length == 1 ? courtIds.single : null;
}

class AcademyService {
  AcademyService._();
  static final instance = AcademyService._();
  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'me-central1');

  Future<OwnerScope> ownerScope() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in is required.');
    final profile = (await _db.collection('users').doc(uid).get()).data();
    final id = profile?['academyId'] as String?;
    if (id == null || id.isEmpty) {
      throw StateError('No academy is assigned to this account.');
    }
    final role = profile?['role']?.toString() ?? '';
    final courtIds = (profile?['courtIds'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toSet();
    final permissions = (profile?['permissions'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toSet();
    if (role == 'courtOwner' && courtIds.length != 1) {
      throw StateError('This court-owner account needs one assigned court.');
    }
    return OwnerScope(
      academyId: id,
      role: role,
      courtIds: courtIds,
      permissions: permissions,
    );
  }

  Future<String> academyId() async => (await ownerScope()).academyId;

  Stream<QuerySnapshot<Map<String, dynamic>>> courts(String academyId) =>
      Stream.fromFuture(ownerScope()).asyncExpand((scope) {
        Query<Map<String, dynamic>> query;
        if (scope.isCourtOwner) {
          query = _db
              .collection('courts')
              .where(FieldPath.documentId, isEqualTo: scope.assignedCourtId);
        } else {
          query = _db
              .collection('courts')
              .where('academyId', isEqualTo: academyId)
              .orderBy('name');
        }
        return query.snapshots();
      });

  Stream<QuerySnapshot<Map<String, dynamic>>> bookings(String academyId) =>
      Stream.fromFuture(ownerScope()).asyncExpand((scope) {
        Query<Map<String, dynamic>> query;
        if (scope.isCourtOwner) {
          query = _db
              .collection('bookings')
              .where('courtId', isEqualTo: scope.assignedCourtId)
              .orderBy('startUtc', descending: true);
        } else {
          query = _db
              .collection('bookings')
              .where('academyId', isEqualTo: academyId)
              .orderBy('startUtc', descending: true);
        }
        return query.limit(200).snapshots();
      });

  Stream<DocumentSnapshot<Map<String, dynamic>>> academy(String academyId) =>
      _db.collection('academies').doc(academyId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> staff(String academyId) => _db
      .collection('users')
      .where('academyId', isEqualTo: academyId)
      .snapshots();

  Future<void> saveAcademy(Map<String, dynamic> values) async {
    final scope = await ownerScope();
    if (!scope.canManageAcademy) {
      throw StateError('Court owners cannot edit the academy profile.');
    }
    final id = scope.academyId;
    await _db.collection('academies').doc(id).set({
      ...values,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> createStaff({
    required String displayName,
    required String email,
    required List<String> permissions,
  }) async {
    final scope = await ownerScope();
    if (!scope.canManageAcademy) {
      throw StateError('Court owners cannot create staff accounts.');
    }
    await _functions.httpsCallable('createAcademyStaff').call({
      'displayName': displayName,
      'email': email,
      'permissions': permissions,
    });
    final trimmedEmail = email.trim();
    try {
      await _functions.httpsCallable('sendPlayUpPasswordReset').call({
        'email': trimmedEmail,
      });
    } catch (error) {
      throw StaffSetupEmailException(trimmedEmail, error);
    }
  }

  String newCourtId() => _db.collection('courts').doc().id;

  Future<String> uploadCourtImage({
    required String courtId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      throw StateError('Court photos must be smaller than 5 MB.');
    }
    final tenantId = (await ownerScope()).academyId;
    final extension = fileName.split('.').last.toLowerCase();
    final contentType = extension == 'png' ? 'image/png' : 'image/jpeg';
    final ref = FirebaseStorage.instance.ref(
      'court-images/$tenantId/$courtId/cover.$extension',
    );
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  Future<String> uploadAcademyImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      throw StateError('Academy photos must be smaller than 5 MB.');
    }
    final scope = await ownerScope();
    if (!scope.canManageAcademy) {
      throw StateError('Only academy owners can edit academy photos.');
    }
    final extension = fileName.split('.').last.toLowerCase();
    final safeExtension =
        const {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'}.contains(extension)
        ? extension
        : 'jpg';
    final contentType = switch (safeExtension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };
    final ref = FirebaseStorage.instance.ref(
      'academy-images/${scope.academyId}/cover.$safeExtension',
    );
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  Future<String> saveCourt({
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
    String timezone = 'Asia/Amman',
    int? peakPriceMinor,
    int? peakHourStart,
    int? peakHourEnd,
  }) async {
    final scope = await ownerScope();
    final tenantId = scope.academyId;
    if (scope.isCourtOwner &&
        (courtId == null || courtId != scope.assignedCourtId)) {
      throw StateError('Court owners can only edit their assigned court.');
    }
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
      'timezone': timezone,
      'active': true,
      'bookable': basePriceMinor > 0,
      'peakPriceMinor': ?peakPriceMinor,
      'peakHourStart': ?peakHourStart,
      'peakHourEnd': ?peakHourEnd,
      'blockedPeriods': <Map<String, dynamic>>[],
      'maintenancePeriods': <Map<String, dynamic>>[],
      'updatedAt': FieldValue.serverTimestamp(),
      if (courtId == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  Future<void> deactivateCourt(String courtId) async {
    final scope = await ownerScope();
    if (scope.isCourtOwner && courtId != scope.assignedCourtId) {
      throw StateError('Court owners can only manage their assigned court.');
    }
    await _db.collection('courts').doc(courtId).update({
      'active': false,
      'bookable': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> transitionBooking(String bookingId, String status) async {
    try {
      await _functions.httpsCallable('transitionBooking').call({
        'bookingId': bookingId,
        'status': status,
      });
    } on FirebaseFunctionsException catch (error) {
      if (!_useFirebaseEmulators || !_callableUnavailable(error)) rethrow;
      final ref = _db.collection('bookings').doc(bookingId);
      final data = (await ref.get()).data();
      if (data == null) throw StateError('Booking not found.');
      final batch = _db.batch();
      batch.update(ref, {
        'status': status,
        '${status}At': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (status == 'cancelled') {
        for (final lockId in List<String>.from(
          data['lockIds'] as List? ?? const [],
        )) {
          batch.delete(_db.collection('bookingLocks').doc(lockId));
        }
      }
      await batch.commit();
    }
  }

  Future<void> recordCashPayment(String bookingId) async {
    try {
      await _functions.httpsCallable('recordCashPayment').call({
        'bookingId': bookingId,
      });
    } on FirebaseFunctionsException catch (error) {
      if (!_useFirebaseEmulators || !_callableUnavailable(error)) rethrow;
      await _db.collection('bookings').doc(bookingId).update({
        'paymentStatus': 'collected',
        'collectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  bool _callableUnavailable(FirebaseFunctionsException error) =>
      error.code == 'not-found' ||
      error.code == 'unimplemented' ||
      (error.message ?? '').toLowerCase().contains('not found');
}
