import 'package:cloud_firestore/cloud_firestore.dart';

import 'flat_billing.dart';

class FlatPaymentLinker {
  static final Map<String, Future<void>> _ownLinks = <String, Future<void>>{};
  static final Map<String, Future<void>> _ownSessionLinks =
      <String, Future<void>>{};
  static Future<void>? _allLinks;

  static Future<void> ensureOwn(String uid, FlatProfileScope scope) {
    if (uid.isEmpty) {
      return Future<void>.value();
    }
    return _ownLinks.putIfAbsent(uid, () async {
      try {
        await _linkOwn(uid, scope);
      } catch (_) {
        _ownLinks.remove(uid);
      }
    });
  }

  static Future<void> ensureOwnSessions(String uid, FlatProfileScope scope) {
    if (uid.isEmpty) {
      return Future<void>.value();
    }
    return _ownSessionLinks.putIfAbsent(uid, () async {
      try {
        final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
            .instance
            .collection('chargingSessions')
            .where('ownerUid', isEqualTo: uid)
            .get();
        await _commitLinks(
          snap.docs,
          (Map<String, dynamic> data) => _sessionHomeFields(data, scope),
        );
      } catch (_) {
        _ownSessionLinks.remove(uid);
      }
    });
  }

  static Future<void> ensureAll() {
    return _allLinks ??= () async {
      try {
        await _linkAll();
      } catch (_) {
        _allLinks = null;
      }
    }();
  }

  static Future<String?> submitPaymentRequest({
    required String uid,
    required String txnRef,
    required double amount,
    required String monthKey,
  }) async {
    final String reference = txnRef.trim().toUpperCase();
    if (uid.isEmpty) {
      return 'Please login first.';
    }
    if (reference.isEmpty || amount <= 0) {
      return 'Enter valid amount and transaction reference.';
    }
    try {
      final DocumentSnapshot<Map<String, dynamic>> userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final FlatProfileScope? scope = FlatProfileScope.fromUser(userDoc.data());
      if (scope == null) {
        return 'Flat details are missing on your profile.';
      }
      await ensureOwn(uid, scope);
      final CollectionReference<Map<String, dynamic>> payments =
          FirebaseFirestore.instance.collection('payments');
      final QuerySnapshot<Map<String, dynamic>> flatSnap =
          await payments.where('billingFlatKey', isEqualTo: scope.key).get();
      final QuerySnapshot<Map<String, dynamic>> ownSnap =
          await payments.where('ownerUid', isEqualTo: uid).get();
      final Map<String, Map<String, dynamic>> merged =
          FlatBillMath.dedupePayments(<MapEntry<String, Map<String, dynamic>>>[
        ...flatSnap.docs.map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              MapEntry<String, Map<String, dynamic>>(doc.id, doc.data()),
        ),
        ...ownSnap.docs.map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              MapEntry<String, Map<String, dynamic>>(doc.id, doc.data()),
        ),
      ]);
      for (final Map<String, dynamic> data in merged.values) {
        if (!FlatBillMath.paymentCounts(
          data: data,
          scope: scope,
          viewerUid: uid,
          monthKey: monthKey,
        )) {
          continue;
        }
        final String status = (data['status'] ?? '').toString();
        if (status == 'submitted') {
          return 'A payment verification request is already pending for this flat this month.';
        }
        if ((data['txnRef'] ?? '').toString() == reference) {
          return 'This transaction reference already exists for this flat this month.';
        }
      }
      await payments.add(<String, dynamic>{
        'ownerUid': uid,
        'txnRef': reference,
        'amount': amount,
        'monthKey': monthKey,
        'status': 'submitted',
        'wing': scope.wing,
        'flatNumber': scope.flat,
        'billingFlatKey': scope.key,
        'requestedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return null;
    } on FirebaseException catch (e) {
      return e.message ?? 'Could not submit the payment request.';
    }
  }

  static Future<void> _linkOwn(String uid, FlatProfileScope scope) async {
    final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
        .instance
        .collection('payments')
        .where('ownerUid', isEqualTo: uid)
        .get();
    await _commitLinks(
      snap.docs,
      (Map<String, dynamic> data) => _residentFields(data, scope),
    );
  }

  static Future<void> _linkAll() async {
    final QuerySnapshot<Map<String, dynamic>> usersSnap =
        await FirebaseFirestore.instance.collection('users').get();
    final Map<String, FlatProfileScope> scopes = <String, FlatProfileScope>{};
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in usersSnap.docs) {
      final FlatProfileScope? scope = FlatProfileScope.fromUser(doc.data());
      if (scope != null) {
        scopes[doc.id] = scope;
      }
    }
    final QuerySnapshot<Map<String, dynamic>> paymentSnap =
        await FirebaseFirestore.instance.collection('payments').get();
    await _commitLinks(
      paymentSnap.docs,
      (Map<String, dynamic> data) {
        final String ownerUid = (data['ownerUid'] ?? '').toString();
        final FlatProfileScope? scope = scopes[ownerUid];
        if (scope == null) {
          return null;
        }
        return _adminFields(data, scope);
      },
    );
    final QuerySnapshot<Map<String, dynamic>> sessionSnap =
        await FirebaseFirestore.instance.collection('chargingSessions').get();
    await _commitLinks(
      sessionSnap.docs,
      (Map<String, dynamic> data) {
        final String ownerUid = (data['ownerUid'] ?? '').toString();
        final FlatProfileScope? scope = scopes[ownerUid];
        if (scope == null) {
          return null;
        }
        return _sessionHomeFields(data, scope);
      },
    );
  }

  /// Keeps the charging-point wing, and records the resident's home wing.
  static Map<String, dynamic>? _sessionHomeFields(
    Map<String, dynamic> data,
    FlatProfileScope scope,
  ) {
    final String flat = (data['flatNumber'] ?? '').toString();
    if (flat != scope.flat) {
      return null;
    }
    if ((data['billingWing'] ?? '').toString() == scope.wing &&
        (data['billingFlatKey'] ?? '').toString() == scope.key) {
      return null;
    }
    return <String, dynamic>{
      'billingWing': scope.wing,
      'billingFlatKey': scope.key,
    };
  }

  /// A resident may only attach their own untagged payment to their current flat.
  static Map<String, dynamic>? _residentFields(
    Map<String, dynamic> data,
    FlatProfileScope scope,
  ) {
    final String existing = (data['billingFlatKey'] ?? '').toString();
    if (existing.isNotEmpty) {
      return null;
    }
    final String? fieldKey =
        FlatBillMath.flatKey(data['wing'], data['flatNumber']);
    if (fieldKey != null && fieldKey != scope.key) {
      return null;
    }
    if (fieldKey == scope.key) {
      return <String, dynamic>{'billingFlatKey': scope.key};
    }
    return scope.paymentFields();
  }

  /// Admin can stamp the flat already stored on a payment without moving it.
  static Map<String, dynamic>? _adminFields(
    Map<String, dynamic> data,
    FlatProfileScope scope,
  ) {
    final String existing = (data['billingFlatKey'] ?? '').toString();
    if (existing.isNotEmpty) {
      return null;
    }
    final String? fieldKey =
        FlatBillMath.flatKey(data['wing'], data['flatNumber']);
    if (fieldKey != null && fieldKey != scope.key) {
      return <String, dynamic>{'billingFlatKey': fieldKey};
    }
    if (fieldKey == scope.key) {
      return <String, dynamic>{'billingFlatKey': scope.key};
    }
    return scope.paymentFields();
  }

  static Future<void> _commitLinks(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, dynamic>? Function(Map<String, dynamic> data) resolve,
  ) async {
    WriteBatch batch = FirebaseFirestore.instance.batch();
    int pending = 0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docs) {
      final Map<String, dynamic>? fields = resolve(doc.data());
      if (fields == null || fields.isEmpty) {
        continue;
      }
      batch.update(doc.reference, fields);
      pending += 1;
      if (pending == 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        pending = 0;
      }
    }
    if (pending > 0) {
      await batch.commit();
    }
  }
}
