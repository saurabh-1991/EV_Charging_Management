import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class SessionRepository {
  SessionRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Future<String> startChargingSession({
    required String ownerUid,
    required String residentName,
    required String wing,
    required int floor,
    required String flatNumber,
    required int chargingPoint,
    required String vehicleNumber,
    required double startMeter,
    required double ratePerUnit,
  }) async {
    final String normalizedFlat = flatNumber.trim().toUpperCase();
    final String pointKey = _pointKey(wing, chargingPoint);
    final DocumentReference<Map<String, dynamic>> slotRef =
        _firestore.collection('chargingSlots').doc(pointKey);
    final CollectionReference<Map<String, dynamic>> sessions =
        _firestore.collection('chargingSessions');
    final Timestamp now = Timestamp.now();
    final DateTime nowDate = now.toDate();
    final String monthKey = DateFormat('yyyy-MM').format(now.toDate());
    final String bookingDateKey = DateFormat('yyyy-MM-dd').format(nowDate);
    final int bookingStartHour = nowDate.hour;
    final String bookingId = '${bookingDateKey}_${pointKey}_$bookingStartHour';
    final DocumentReference<Map<String, dynamic>> bookingRef =
        _firestore.collection('slotBookings').doc(bookingId);

    return _firestore.runTransaction<String>((Transaction txn) async {
      final DocumentSnapshot<Map<String, dynamic>> slotDoc =
          await txn.get(slotRef);
      if (slotDoc.exists && slotDoc.data()?['occupied'] == true) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'slot-occupied',
          message: '$pointKey is currently unavailable.',
        );
      }

      final DocumentReference<Map<String, dynamic>> sessionRef = sessions.doc();
      final DocumentSnapshot<Map<String, dynamic>> bookingDoc =
          await txn.get(bookingRef);
      if (bookingDoc.exists) {
        final Map<String, dynamic> booking =
            bookingDoc.data() ?? <String, dynamic>{};
        final String status = (booking['status'] ?? '').toString();
        final String bookingOwner = (booking['ownerUid'] ?? '').toString();
        if (status == 'booked') {
          if (bookingOwner == ownerUid) {
            txn.update(bookingRef, <String, dynamic>{
              'status': 'used',
              'usedSessionId': sessionRef.id,
              'updatedAt': now,
            });
          } else {
            txn.update(bookingRef, <String, dynamic>{
              'status': 'overridden',
              'overriddenByUid': ownerUid,
              'overriddenSessionId': sessionRef.id,
              'updatedAt': now,
            });
          }
        }
      }

      txn.set(sessionRef, <String, dynamic>{
        'ownerUid': ownerUid,
        'residentName': residentName,
        'wing': wing,
        'floor': floor,
        'flat': normalizedFlat,
        'flatNumber': normalizedFlat,
        'chargingPoint': chargingPoint,
        'pointKey': pointKey,
        'vehicleNumber': vehicleNumber.toUpperCase(),
        'startMeter': startMeter,
        'endMeter': null,
        'ratePerUnit': ratePerUnit,
        'units': null,
        'amount': null,
        'status': 'active',
        'monthKey': monthKey,
        'startTime': now,
        'endTime': null,
        'createdAt': now,
        'updatedAt': now,
      });

      txn.set(
          slotRef,
          <String, dynamic>{
            'wing': wing,
            'chargingPoint': chargingPoint,
            'pointKey': pointKey,
            'occupied': true,
            'currentSessionId': sessionRef.id,
            'residentName': residentName,
            'flatNumber': normalizedFlat,
            'vehicleNumber': vehicleNumber.toUpperCase(),
            'startedAt': now,
            'updatedAt': now,
          },
          SetOptions(merge: true));

      final String vehicleDocId = _vehicleDocId(vehicleNumber);
      txn.set(
          _firestore.collection('vehicles').doc(vehicleDocId),
          <String, dynamic>{
            'vehicleNumber': vehicleNumber.toUpperCase(),
            'wing': wing,
            'flatNumber': normalizedFlat,
            'lastChargedAt': now,
            'updatedAt': now,
          },
          SetOptions(merge: true));

      return sessionRef.id;
    });
  }

  Future<void> stopChargingSession({
    required String ownerUid,
    required String pointKey,
    required double endMeter,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> activeSessionSnap =
        await _firestore
            .collection('chargingSessions')
            .where('ownerUid', isEqualTo: ownerUid)
            .where('pointKey', isEqualTo: pointKey)
            .where('status', isEqualTo: 'active')
            .limit(1)
            .get();

    if (activeSessionSnap.docs.isEmpty) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'no-active-session',
        message: 'No active charging session found for $pointKey.',
      );
    }

    final DocumentReference<Map<String, dynamic>> sessionRef =
        activeSessionSnap.docs.first.reference;
    final DocumentReference<Map<String, dynamic>> slotRef =
        _firestore.collection('chargingSlots').doc(pointKey);
    final Timestamp now = Timestamp.now();
    final String monthKey = DateFormat('yyyy-MM').format(now.toDate());

    await _firestore.runTransaction((Transaction txn) async {
      final DocumentSnapshot<Map<String, dynamic>> sessionDoc =
          await txn.get(sessionRef);
      final Map<String, dynamic>? data = sessionDoc.data();
      if (data == null) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'session-missing',
          message: 'Active charging session data not found.',
        );
      }

      final double startMeter = (data['startMeter'] as num?)?.toDouble() ?? 0;
      final double rate = (data['ratePerUnit'] as num?)?.toDouble() ?? 0;
      if (endMeter <= startMeter) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'invalid-meter',
          message: 'End meter must be greater than start meter.',
        );
      }

      final double units = endMeter - startMeter;
      final double amount = units * rate;

      txn.update(sessionRef, <String, dynamic>{
        'endMeter': endMeter,
        'units': units,
        'amount': amount,
        'status': 'completed',
        'monthKey': monthKey,
        'endTime': now,
        'updatedAt': now,
      });

      txn.set(
          slotRef,
          <String, dynamic>{
            'occupied': false,
            'currentSessionId': null,
            'residentName': null,
            'flatNumber': null,
            'vehicleNumber': null,
            'updatedAt': now,
          },
          SetOptions(merge: true));

      final String vehicleNumber = (data['vehicleNumber'] ?? '').toString();
      final String vehicleDocId = _vehicleDocId(vehicleNumber);
      txn.set(
          _firestore.collection('vehicles').doc(vehicleDocId),
          <String, dynamic>{
            'totalSessions': FieldValue.increment(1),
            'totalUnits': FieldValue.increment(units),
            'updatedAt': now,
          },
          SetOptions(merge: true));
    });
  }

  Stream<Map<String, PointSlotStatus>> watchPointStatuses() {
    return _firestore.collection('chargingSlots').snapshots().map(
      (QuerySnapshot<Map<String, dynamic>> snapshot) {
        final Map<String, PointSlotStatus> statuses =
            <String, PointSlotStatus>{};
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snapshot.docs) {
          final Map<String, dynamic> data = doc.data();
          statuses[doc.id] = PointSlotStatus(
            pointKey: doc.id,
            occupied: data['occupied'] == true,
            residentName: (data['residentName'] ?? '').toString(),
            flatNumber: (data['flatNumber'] ?? '').toString(),
            vehicleNumber: (data['vehicleNumber'] ?? '').toString(),
            startedAt: (data['startedAt'] as Timestamp?)?.toDate(),
          );
        }
        return statuses;
      },
    );
  }

  Stream<ChargingSession?> watchActiveSessionForPoint(String pointKey) {
    return _firestore
        .collection('chargingSessions')
        .where('pointKey', isEqualTo: pointKey)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
      if (snapshot.docs.isEmpty) {
        return null;
      }
      return _fromDoc(snapshot.docs.first);
    });
  }

  Stream<List<ChargingSession>> watchRecentSessions({
    String? ownerUid,
    String? vehicleFilter,
    String? wingFilter,
    String? flatNumberFilter,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('chargingSessions')
        .orderBy('createdAt', descending: true)
        .limit(100);

    final String owner = (ownerUid ?? '').trim();
    if (owner.isNotEmpty) {
      query = query.where('ownerUid', isEqualTo: owner);
    }
    final String filter = (vehicleFilter ?? '').trim().toUpperCase();
    if (filter.isNotEmpty) {
      query = query.where('vehicleNumber', isEqualTo: filter);
    }
    final String wing = (wingFilter ?? '').trim().toUpperCase();
    if (wing.isNotEmpty) {
      query = query.where('wing', isEqualTo: wing);
    }
    final String flatNumber = (flatNumberFilter ?? '').trim().toUpperCase();
    if (flatNumber.isNotEmpty) {
      query = query.where('flatNumber', isEqualTo: flatNumber);
    }

    return query
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
      return snapshot.docs.map(_fromDoc).toList();
    });
  }

  Future<List<ChargingSession>> fetchAllSessionsForExport({
    String? ownerUid,
    String? wingFilter,
    String? flatNumberFilter,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('chargingSessions')
        .orderBy('createdAt', descending: false);

    final String owner = (ownerUid ?? '').trim();
    if (owner.isNotEmpty) {
      query = query.where('ownerUid', isEqualTo: owner);
    }
    final String wing = (wingFilter ?? '').trim().toUpperCase();
    if (wing.isNotEmpty) {
      query = query.where('wing', isEqualTo: wing);
    }
    final String flatNumber = (flatNumberFilter ?? '').trim().toUpperCase();
    if (flatNumber.isNotEmpty) {
      query = query.where('flatNumber', isEqualTo: flatNumber);
    }

    final QuerySnapshot<Map<String, dynamic>> snapshot = await query.get();
    return snapshot.docs.map(_fromDoc).toList();
  }

  ChargingSession _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data();
    return ChargingSession(
      id: doc.id,
      residentName: (data['residentName'] ?? '').toString(),
      wing: (data['wing'] ?? '').toString(),
      floor: (data['floor'] as num?)?.toInt() ?? 0,
      flat: (data['flat'] ?? '').toString(),
      flatNumber: (data['flatNumber'] ?? '').toString(),
      chargingPoint: (data['chargingPoint'] as num?)?.toInt() ?? 0,
      pointKey: (data['pointKey'] ?? '').toString(),
      vehicleNumber: (data['vehicleNumber'] ?? '').toString(),
      startMeter: (data['startMeter'] as num?)?.toDouble() ?? 0,
      endMeter: (data['endMeter'] as num?)?.toDouble() ?? 0,
      ratePerUnit: (data['ratePerUnit'] as num?)?.toDouble() ?? 0,
      units: (data['units'] as num?)?.toDouble() ?? 0,
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      status: (data['status'] ?? 'completed').toString(),
      startTime: (data['startTime'] as Timestamp?)?.toDate(),
      endTime: (data['endTime'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  String _vehicleDocId(String vehicleNumber) {
    return vehicleNumber
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '_');
  }

  String _pointKey(String wing, int point) => '${wing.toUpperCase()}-P$point';
}

class PointSlotStatus {
  PointSlotStatus({
    required this.pointKey,
    required this.occupied,
    required this.residentName,
    required this.flatNumber,
    required this.vehicleNumber,
    required this.startedAt,
  });

  final String pointKey;
  final bool occupied;
  final String residentName;
  final String flatNumber;
  final String vehicleNumber;
  final DateTime? startedAt;
}

class ChargingSession {
  ChargingSession({
    required this.id,
    required this.residentName,
    required this.wing,
    required this.floor,
    required this.flat,
    required this.flatNumber,
    required this.chargingPoint,
    required this.pointKey,
    required this.vehicleNumber,
    required this.startMeter,
    required this.endMeter,
    required this.ratePerUnit,
    required this.units,
    required this.amount,
    required this.status,
    required this.startTime,
    required this.endTime,
    required this.createdAt,
  });

  final String id;
  final String residentName;
  final String wing;
  final int floor;
  final String flat;
  final String flatNumber;
  final int chargingPoint;
  final String pointKey;
  final String vehicleNumber;
  final double startMeter;
  final double endMeter;
  final double ratePerUnit;
  final double units;
  final double amount;
  final String status;
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime createdAt;
}
