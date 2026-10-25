import 'package:ev_charging_management/core/flat_billing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const FlatProfileScope b2 = FlatProfileScope(wing: 'B2', flat: '805');
  const FlatProfileScope b1 = FlatProfileScope(wing: 'B1', flat: '805');

  test('blank flat is not grouped with other blank profiles', () {
    expect(FlatProfileScope.fromUser(<String, dynamic>{'wing': 'B2'}), isNull);
    expect(
      FlatProfileScope.fromUser(
          <String, dynamic>{'wing': ' ', 'flatNumber': '805'}),
      isNull,
    );
    expect(
      FlatProfileScope.fromUser(
        <String, dynamic>{'wing': 'B2', 'flatNumber': '805'},
      )?.key,
      'B2|805',
    );
  });

  test('same flat number in another wing stays separate', () {
    expect(
      FlatBillMath.sessionCounts(
        data: <String, dynamic>{
          'status': 'completed',
          'wing': 'B1',
          'flatNumber': '805',
          'units': 4,
          'amount': 60,
          'monthKey': '2026-10',
        },
        scope: b2,
        viewerUid: 'user-a',
        monthKey: '2026-10',
      ),
      isFalse,
    );
  });

  test('flat bill adds both accounts and ignores another flat', () {
    final FlatBillTotals totals = FlatBillMath.summarize(
      sessions: <Map<String, dynamic>>[
        <String, dynamic>{
          'status': 'completed',
          'wing': 'B2',
          'flatNumber': '805',
          'ownerUid': 'user-a',
          'units': 10,
          'amount': 150,
          'monthKey': '2026-10',
        },
        <String, dynamic>{
          'status': 'completed',
          'wing': 'B2',
          'flatNumber': '805',
          'ownerUid': 'user-b',
          'units': 2,
          'amount': 30,
          'monthKey': '2026-10',
        },
        <String, dynamic>{
          'status': 'active',
          'wing': 'B2',
          'flatNumber': '805',
          'ownerUid': 'user-a',
          'units': 99,
          'amount': 999,
          'monthKey': '2026-10',
        },
        <String, dynamic>{
          'status': 'completed',
          'wing': 'B1',
          'flatNumber': '805',
          'ownerUid': 'user-c',
          'units': 8,
          'amount': 120,
          'monthKey': '2026-10',
        },
        <String, dynamic>{
          'status': 'completed',
          'wing': 'B2',
          'flatNumber': '805',
          'ownerUid': 'user-a',
          'units': 5,
          'amount': 75,
          'monthKey': '2026-09',
        },
      ],
      payments: <Map<String, dynamic>>[
        <String, dynamic>{
          'billingFlatKey': 'B2|805',
          'ownerUid': 'user-b',
          'status': 'paid',
          'amount': 100,
          'monthKey': '2026-10',
        },
        <String, dynamic>{
          'billingFlatKey': 'B2|805',
          'ownerUid': 'user-a',
          'status': 'verified',
          'amount': 20,
          'monthKey': '2026-10',
        },
        <String, dynamic>{
          'billingFlatKey': 'B2|805',
          'ownerUid': 'user-a',
          'status': 'rejected',
          'amount': 50,
          'monthKey': '2026-10',
        },
        <String, dynamic>{
          'billingFlatKey': 'B1|805',
          'ownerUid': 'user-a',
          'status': 'paid',
          'amount': 80,
          'monthKey': '2026-10',
        },
        <String, dynamic>{
          'ownerUid': 'user-a',
          'status': 'paid',
          'amount': 15,
          'monthKey': '2026-10',
        },
        <String, dynamic>{
          'ownerUid': 'user-b',
          'status': 'paid',
          'amount': 40,
          'monthKey': '2026-10',
        },
      ],
      scope: b2,
      viewerUid: 'user-a',
      monthKey: '2026-10',
    );

    expect(totals.units, 12);
    expect(totals.billed, 180);
    expect(totals.paid, 135);
    expect(totals.due, 45);
    expect(
      FlatBillMath.summarize(
        sessions: <Map<String, dynamic>>[
          <String, dynamic>{
            'status': 'completed',
            'wing': 'B1',
            'flatNumber': '805',
            'units': 8,
            'amount': 120,
            'monthKey': '2026-10',
          },
        ],
        payments: <Map<String, dynamic>>[
          <String, dynamic>{
            'billingFlatKey': 'B2|805',
            'status': 'paid',
            'amount': 100,
            'monthKey': '2026-10',
          },
        ],
        scope: b1,
        viewerUid: 'user-c',
        monthKey: '2026-10',
      ).paid,
      0,
    );
  });

  test('overpayment does not create a negative due', () {
    final FlatBillTotals totals = FlatBillMath.summarize(
      sessions: <Map<String, dynamic>>[
        <String, dynamic>{
          'status': 'completed',
          'wing': 'B2',
          'flatNumber': '805',
          'units': 1,
          'amount': 15,
        },
      ],
      payments: <Map<String, dynamic>>[
        <String, dynamic>{
          'billingFlatKey': 'B2|805',
          'status': 'paid',
          'amount': 40,
        },
      ],
      scope: b2,
      viewerUid: 'user-a',
    );
    expect(totals.due, 0);
  });

  test('duplicate payment documents are counted once', () {
    final Map<String, Map<String, dynamic>> merged =
        FlatBillMath.dedupePayments(
      <MapEntry<String, Map<String, dynamic>>>[
        MapEntry<String, Map<String, dynamic>>('p1', <String, dynamic>{
          'billingFlatKey': 'B2|805',
          'status': 'paid',
          'amount': 10,
        }),
        MapEntry<String, Map<String, dynamic>>('p1', <String, dynamic>{
          'billingFlatKey': 'B2|805',
          'status': 'paid',
          'amount': 10,
        }),
      ],
    );
    final FlatBillTotals totals = FlatBillMath.summarize(
      sessions: <Map<String, dynamic>>[],
      payments: merged.values,
      scope: b2,
      viewerUid: 'user-a',
    );
    expect(merged, hasLength(1));
    expect(totals.paid, 10);
  });
}
