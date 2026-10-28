import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'flat_billing.dart';

/// Loads every completed charge for the signed-in account, plus charges for
/// the same home flat. A B2 flat can include sessions taken at a B1 point.
class FlatSessionMerge extends StatelessWidget {
  const FlatSessionMerge({
    required this.uid,
    required this.scope,
    required this.builder,
    super.key,
  });

  final String uid;
  final FlatProfileScope? scope;
  final Widget Function(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs)
      builder;

  @override
  Widget build(BuildContext context) {
    final CollectionReference<Map<String, dynamic>> sessions =
        FirebaseFirestore.instance.collection('chargingSessions');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: sessions.where('ownerUid', isEqualTo: uid).snapshots(),
      builder: (BuildContext context,
          AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> ownSnap) {
        final FlatProfileScope? flatScope = scope;
        if (flatScope == null) {
          return _ready(ownSnap, null, null);
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: sessions
              .where('wing', isEqualTo: flatScope.wing)
              .where('flatNumber', isEqualTo: flatScope.flat)
              .snapshots(),
          builder: (BuildContext context,
              AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> wingSnap) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: sessions
                  .where('billingWing', isEqualTo: flatScope.wing)
                  .where('flatNumber', isEqualTo: flatScope.flat)
                  .snapshots(),
              builder: (BuildContext context,
                  AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> homeSnap) {
                return _ready(ownSnap, wingSnap, homeSnap);
              },
            );
          },
        );
      },
    );
  }

  Widget _ready(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> ownSnap,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>? wingSnap,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>? homeSnap,
  ) {
    if (ownSnap.hasError || (wingSnap?.hasError ?? false)) {
      return Text('Unable to load bills: ${ownSnap.error ?? wingSnap?.error}');
    }
    if (!ownSnap.hasData || (wingSnap != null && !wingSnap.hasData)) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> merged =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    void addAll(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docs) {
        merged[doc.id] = doc;
      }
    }

    addAll(ownSnap.data!.docs);
    if (wingSnap != null) {
      addAll(wingSnap.data!.docs);
    }
    // Missing index should not hide the account's own B1 and B2 charges.
    if (homeSnap != null && homeSnap.hasData) {
      addAll(homeSnap.data!.docs);
    }
    return builder(merged.values.toList());
  }
}
