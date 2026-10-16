import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  static const String routeName = '/billing';

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  DateTime _selectedMonth = DateTime.now();

  String get _monthKey => DateFormat('yyyy-MM').format(_selectedMonth);

  Future<void> _pickMonth() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly Billing')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_month),
            label: Text(DateFormat('MMMM yyyy').format(_selectedMonth)),
          ),
          const SizedBox(height: 12),
          if (uid.isEmpty)
            const Text('Please login to view billing.')
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chargingSessions')
                  .where('ownerUid', isEqualTo: uid)
                  .where('status', isEqualTo: 'completed')
                  .where('monthKey', isEqualTo: _monthKey)
                  .snapshots(),
              builder: (BuildContext context,
                  AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>
                      sessionSnap) {
                if (sessionSnap.hasError) {
                  return Text('Unable to load bills: ${sessionSnap.error}');
                }
                if (!sessionSnap.hasData) {
                  return const CircularProgressIndicator();
                }
                double units = 0;
                double amount = 0;
                for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                    in sessionSnap.data!.docs) {
                  final Map<String, dynamic> data = doc.data();
                  units += (data['units'] as num?)?.toDouble() ?? 0;
                  amount += (data['amount'] as num?)?.toDouble() ?? 0;
                }
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('payments')
                      .where('ownerUid', isEqualTo: uid)
                      .where('monthKey', isEqualTo: _monthKey)
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (BuildContext context,
                      AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>
                          paymentSnap) {
                    if (paymentSnap.hasError) {
                      return Text('Payments load failed: ${paymentSnap.error}');
                    }
                    final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                        payments = paymentSnap.data?.docs ??
                            <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    double verified = 0;
                    int pendingCount = 0;
                    int rejectedCount = 0;
                    for (final QueryDocumentSnapshot<Map<String, dynamic>> p
                        in payments) {
                      final Map<String, dynamic> data = p.data();
                      final String status =
                          (data['status'] ?? 'submitted').toString();
                      final double paidAmount =
                          (data['amount'] as num?)?.toDouble() ?? 0;
                      if (status == 'verified') {
                        verified += paidAmount;
                      } else if (status == 'submitted') {
                        pendingCount += 1;
                      } else if (status == 'rejected') {
                        rejectedCount += 1;
                      }
                    }
                    String overallStatus = 'Pending';
                    if (amount > 0 && verified >= amount) {
                      overallStatus = 'Paid';
                    } else if (pendingCount > 0) {
                      overallStatus = 'Submitted';
                    } else if (rejectedCount > 0) {
                      overallStatus = 'Rejected';
                    }
                    return Column(
                      children: <Widget>[
                        _BillCard(
                          month: DateFormat('MMMM yyyy').format(_selectedMonth),
                          units: units.toStringAsFixed(2),
                          amount: amount.toStringAsFixed(2),
                          status: overallStatus,
                        ),
                        Card(
                          child: ListTile(
                            title: const Text('Payment Summary'),
                            subtitle: Text(
                              'Verified: INR ${verified.toStringAsFixed(2)} | Pending refs: $pendingCount',
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: uid.isEmpty
                ? null
                : FirebaseFirestore.instance
                    .collection('payments')
                    .where('ownerUid', isEqualTo: uid)
                    .where('monthKey', isEqualTo: _monthKey)
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
            builder: (BuildContext context,
                AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
              if (uid.isEmpty) {
                return const SizedBox.shrink();
              }
              if (snap.hasError) {
                return Text('Payments load failed: ${snap.error}');
              }
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return const Text(
                    'No payment references submitted for this month.');
              }
              return Column(
                children: snap.data!.docs
                    .map((QueryDocumentSnapshot<Map<String, dynamic>> d) {
                  final Map<String, dynamic> data = d.data();
                  return Card(
                    child: ListTile(
                      title: Text(
                        'Txn ${data['txnRef'] ?? '-'} | INR ${((data['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                      ),
                      subtitle:
                          Text('Status: ${data['status'] ?? 'submitted'}'),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({
    required this.month,
    required this.units,
    required this.amount,
    required this.status,
  });

  final String month;
  final String units;
  final String amount;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(month),
        subtitle: Text('Units: $units kWh | Amount: INR $amount'),
        trailing: Chip(label: Text(status)),
      ),
    );
  }
}
