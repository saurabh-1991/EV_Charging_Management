import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/flat_billing.dart';

class SessionRepository {
  SessionRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Future<String> startChargingSession({
    required String ownerUid,
    required String residentName,
    required String wing,
    String? billingWing,
    required int floor,
    required String flatNumber,
    required int chargingPoint,
    required String vehicleNumber,
    required bool isGuestVehicle,
    required double startMeter,
    required double ratePerUnit,
  }) async {
    if (startMeter < 0) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-meter',
        message: 'Start meter cannot be negative.',
      );
    }
    final String normalizedWing = wing.trim();
    final String homeWing = (billingWing ?? normalizedWing).trim();
    final String normalizedFlat = flatNumber.trim().toUpperCase();
    final String? billingFlatKey =
        FlatBillMath.flatKey(homeWing, normalizedFlat);
    final String normalizedVehicle = vehicleNumber.trim().toUpperCase();
    if (normalizedVehicle.isEmpty) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-vehicle',
        message: 'Vehicle number is required.',
      );
    }
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

    final String sessionId =
        await _firestore.runTransaction<String>((Transaction txn) async {
      final DocumentSnapshot<Map<String, dynamic>> slotDoc =
          await txn.get(slotRef);
      if (slotDoc.exists && slotDoc.data()?['occupied'] == true) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'slot-occupied',
          message: '$pointKey is currently unavailable.',
        );
      }
      final double? lastEndMeter =
          (slotDoc.data()?['lastEndMeter'] as num?)?.toDouble();
      if (lastEndMeter != null && startMeter <= lastEndMeter) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'invalid-meter',
          message:
              'Start meter must be greater than the last end meter (${lastEndMeter.toStringAsFixed(2)}) for $pointKey.',
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
        'billingOwnerUid': ownerUid,
        'residentName': residentName,
        'wing': normalizedWing,
        'billingWing': homeWing,
        if (billingFlatKey != null) 'billingFlatKey': billingFlatKey,
        'floor': floor,
        'flat': normalizedFlat,
        'billingFlatNumber': normalizedFlat,
        'flatNumber': normalizedFlat,
        'chargingPoint': chargingPoint,
        'pointKey': pointKey,
        'vehicleNumber': normalizedVehicle,
        'isGuestVehicle': isGuestVehicle,
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
            'vehicleNumber': normalizedVehicle,
            'startedAt': now,
            'updatedAt': now,
          },
          SetOptions(merge: true));

      return sessionRef.id;
    });

    // Non-critical analytics/profile data should not block charging.
    await _upsertVehicleBestEffort(
      vehicleNumber: normalizedVehicle,
      wing: wing,
      flatNumber: normalizedFlat,
      lastChargedAt: now.toDate(),
    );
    return sessionId;
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

    final Map<String, dynamic> completedData = await _firestore
        .runTransaction<Map<String, dynamic>>((Transaction txn) async {
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
            'lastEndMeter': endMeter,
            'lastEndedAt': now,
            'lastMeterSetByAdmin': false,
            'pointKey': pointKey,
            'updatedAt': now,
          },
          SetOptions(merge: true));
      return <String, dynamic>{
        'vehicleNumber': (data['vehicleNumber'] ?? '').toString(),
        'units': units,
      };
    });

    await _incrementVehicleTotalsBestEffort(
      vehicleNumber: completedData['vehicleNumber']?.toString() ?? '',
      units: (completedData['units'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<void> setLastEndMeter({
    required String pointKey,
    required double? meter,
  }) async {
    if (meter != null && meter < 0) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-meter',
        message: 'Meter reading cannot be negative.',
      );
    }
    final DocumentReference<Map<String, dynamic>> slotRef =
        _firestore.collection('chargingSlots').doc(pointKey);
    final DocumentSnapshot<Map<String, dynamic>> slot = await slotRef.get();
    if (slot.data()?['occupied'] == true) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'slot-occupied',
        message: '$pointKey is charging. Correct the reading after it stops.',
      );
    }
    await slotRef.set(
      <String, dynamic>{
        'pointKey': pointKey,
        'lastEndMeter': meter ?? FieldValue.delete(),
        'lastEndedAt': meter == null
            ? FieldValue.delete()
            : FieldValue.serverTimestamp(),
        'lastMeterSetByAdmin': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> ensureLastEndMeters() async {
    const List<String> points = <String>[
      'B1-P1',
      'B1-P2',
      'B2-P1',
      'B2-P2',
    ];
    try {
      final QuerySnapshot<Map<String, dynamic>> completed = await _firestore
          .collection('chargingSessions')
          .where('status', isEqualTo: 'completed')
          .get();
      final Map<String, double> bestMeter = <String, double>{};
      final Map<String, DateTime> bestAt = <String, DateTime>{};
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in completed.docs) {
        final Map<String, dynamic> data = doc.data();
        final String pointKey = (data['pointKey'] ?? '').toString();
        if (!points.contains(pointKey)) {
          continue;
        }
        final double? endMeter = (data['endMeter'] as num?)?.toDouble();
        if (endMeter == null) {
          continue;
        }
        final DateTime endedAt = (data['endTime'] as Timestamp?)?.toDate() ??
            (data['updatedAt'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final DateTime? previous = bestAt[pointKey];
        if (previous == null || endedAt.isAfter(previous)) {
          bestAt[pointKey] = endedAt;
          bestMeter[pointKey] = endMeter;
        }
      }
      for (final MapEntry<String, double> entry in bestMeter.entries) {
        final DocumentReference<Map<String, dynamic>> slotRef =
            _firestore.collection('chargingSlots').doc(entry.key);
        await _firestore.runTransaction((Transaction txn) async {
          final DocumentSnapshot<Map<String, dynamic>> slot =
              await txn.get(slotRef);
          if (slot.data()?['lastMeterSetByAdmin'] == true) {
            return;
          }
          final DateTime? storedAt =
              (slot.data()?['lastEndedAt'] as Timestamp?)?.toDate();
          final DateTime endedAt = bestAt[entry.key]!;
          if (storedAt != null && !endedAt.isAfter(storedAt)) {
            return;
          }
          txn.set(
            slotRef,
            <String, dynamic>{
              'pointKey': entry.key,
              'lastEndMeter': entry.value,
              'lastEndedAt': Timestamp.fromDate(endedAt),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        });
      }
    } catch (_) {
      // Residents cannot list every session. The slot value is still
      // updated each time a session at that point is stopped.
    }
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
            lastEndMeter: (data['lastEndMeter'] as num?)?.toDouble(),
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

  Stream<ChargingSession?> watchActiveSessionForOwner(String ownerUid) {
    return _firestore
        .collection('chargingSessions')
        .where('ownerUid', isEqualTo: ownerUid)
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
      isGuestVehicle: data['isGuestVehicle'] == true,
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

  Future<void> _upsertVehicleBestEffort({
    required String vehicleNumber,
    required String wing,
    required String flatNumber,
    required DateTime lastChargedAt,
  }) async {
    try {
      final String vehicleDocId = _vehicleDocId(vehicleNumber);
      await _firestore.collection('vehicles').doc(vehicleDocId).set(
        <String, dynamic>{
          'vehicleNumber': vehicleNumber,
          'wing': wing,
          'flatNumber': flatNumber,
          'lastChargedAt': Timestamp.fromDate(lastChargedAt),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Intentionally ignored to keep start/stop charging resilient.
    }
  }

  Future<void> _incrementVehicleTotalsBestEffort({
    required String vehicleNumber,
    required double units,
  }) async {
    if (vehicleNumber.trim().isEmpty) {
      return;
    }
    try {
      final String vehicleDocId = _vehicleDocId(vehicleNumber);
      await _firestore.collection('vehicles').doc(vehicleDocId).set(
        <String, dynamic>{
          'totalSessions': FieldValue.increment(1),
          'totalUnits': FieldValue.increment(units),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Intentionally ignored to keep start/stop charging resilient.
    }
  }
}

class PointSlotStatus {
  PointSlotStatus({
    required this.pointKey,
    required this.occupied,
    required this.residentName,
    required this.flatNumber,
    required this.vehicleNumber,
    required this.startedAt,
    required this.lastEndMeter,
  });

  final String pointKey;
  final bool occupied;
  final String residentName;
  final String flatNumber;
  final String vehicleNumber;
  final DateTime? startedAt;
  final double? lastEndMeter;
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
    required this.isGuestVehicle,
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
  final bool isGuestVehicle;
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime createdAt;
}
