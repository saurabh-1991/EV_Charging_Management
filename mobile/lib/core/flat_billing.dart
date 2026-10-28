class FlatProfileScope {
  const FlatProfileScope({
    required this.wing,
    required this.flat,
  }) : key = '$wing|$flat';

  final String wing;
  final String flat;
  final String key;

  /// Uses the profile values exactly. Firestore rules compare those same
  /// strings, so trimming or changing case here would make the query fail
  /// or attach a payment to the wrong flat.
  static FlatProfileScope? fromUser(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final String wing = (data['wing'] ?? '').toString();
    final String flat = (data['flatNumber'] ?? '').toString();
    if (wing.trim().isEmpty || flat.trim().isEmpty) {
      return null;
    }
    return FlatProfileScope(wing: wing, flat: flat);
  }

  Map<String, dynamic> paymentFields() {
    return <String, dynamic>{
      'wing': wing,
      'flatNumber': flat,
      'billingFlatKey': key,
    };
  }
}

class FlatBillTotals {
  const FlatBillTotals({
    required this.units,
    required this.billed,
    required this.paid,
  });

  final double units;
  final double billed;
  final double paid;

  double get due {
    final double raw = billed - paid;
    return raw < 0 ? 0 : raw;
  }
}

class FlatBillMath {
  static String? flatKey(Object? wing, Object? flat) {
    final String normalizedWing = (wing ?? '').toString();
    final String normalizedFlat = (flat ?? '').toString();
    if (normalizedWing.trim().isEmpty || normalizedFlat.trim().isEmpty) {
      return null;
    }
    return '$normalizedWing|$normalizedFlat';
  }

  static bool isSettledStatus(String status) {
    return status == 'paid' || status == 'verified';
  }

  static bool sessionCounts({
    required Map<String, dynamic> data,
    required FlatProfileScope? scope,
    required String viewerUid,
    String? monthKey,
  }) {
    if ((data['status'] ?? '').toString() != 'completed') {
      return false;
    }
    if (monthKey != null && (data['monthKey'] ?? '').toString() != monthKey) {
      return false;
    }
    if (scope == null) {
      return (data['ownerUid'] ?? '').toString() == viewerUid;
    }
    final String flat = (data['flatNumber'] ?? '').toString();
    final String homeWing = (data['billingWing'] ?? '').toString();
    final String pointWing = (data['wing'] ?? '').toString();
    final String ownerUid = (data['ownerUid'] ?? '').toString();
    if (homeWing.isNotEmpty) {
      return homeWing == scope.wing && flat == scope.flat;
    }
    if (ownerUid == viewerUid && flat == scope.flat) {
      // Charging-point wing can be B1 while the flat's home wing is B2.
      return true;
    }
    return pointWing == scope.wing && flat == scope.flat;
  }

  /// A payment reduces only the flat stored on it.
  /// Untagged legacy payments stay with the account that created them until
  /// that account links them, and are never copied onto a different flat.
  static bool paymentCounts({
    required Map<String, dynamic> data,
    required FlatProfileScope? scope,
    required String viewerUid,
    String? monthKey,
  }) {
    if (monthKey != null && (data['monthKey'] ?? '').toString() != monthKey) {
      return false;
    }
    if (scope == null) {
      return (data['ownerUid'] ?? '').toString() == viewerUid;
    }
    final String tagged = (data['billingFlatKey'] ?? '').toString();
    if (tagged.isNotEmpty) {
      return tagged == scope.key;
    }
    final String? fieldKey = flatKey(data['wing'], data['flatNumber']);
    if (fieldKey != null) {
      return fieldKey == scope.key;
    }
    return (data['ownerUid'] ?? '').toString() == viewerUid;
  }

  static FlatBillTotals summarize({
    required Iterable<Map<String, dynamic>> sessions,
    required Iterable<Map<String, dynamic>> payments,
    required FlatProfileScope? scope,
    required String viewerUid,
    String? monthKey,
  }) {
    double units = 0;
    double billed = 0;
    for (final Map<String, dynamic> data in sessions) {
      if (!sessionCounts(
        data: data,
        scope: scope,
        viewerUid: viewerUid,
        monthKey: monthKey,
      )) {
        continue;
      }
      units += (data['units'] as num?)?.toDouble() ?? 0;
      billed += (data['amount'] as num?)?.toDouble() ?? 0;
    }
    double paid = 0;
    for (final Map<String, dynamic> data in payments) {
      if (!paymentCounts(
        data: data,
        scope: scope,
        viewerUid: viewerUid,
        monthKey: monthKey,
      )) {
        continue;
      }
      if (!isSettledStatus((data['status'] ?? '').toString())) {
        continue;
      }
      paid += (data['amount'] as num?)?.toDouble() ?? 0;
    }
    return FlatBillTotals(units: units, billed: billed, paid: paid);
  }

  static Map<String, Map<String, dynamic>> dedupePayments(
    Iterable<MapEntry<String, Map<String, dynamic>>> docs,
  ) {
    final Map<String, Map<String, dynamic>> merged =
        <String, Map<String, dynamic>>{};
    for (final MapEntry<String, Map<String, dynamic>> doc in docs) {
      merged[doc.key] = doc.value;
    }
    return merged;
  }
}
