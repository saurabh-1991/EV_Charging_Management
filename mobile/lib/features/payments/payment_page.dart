import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../core/flat_payment_linker.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({required this.firebaseReady, super.key});

  static const String routeName = '/payments';
  final bool firebaseReady;

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final TextEditingController _txnRefController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _txnRefController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submitPaymentReference() async {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final double amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final String? error = await FlatPaymentLinker.submitPaymentRequest(
      uid: uid,
      txnRef: _txnRefController.text,
      amount: amount,
      monthKey: DateFormat('yyyy-MM').format(DateTime.now()),
    );
    if (!mounted) {
      return;
    }
    if (error != null) {
      _toast(error);
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _submitted = true;
    });
    _toast('Reference submitted for admin verification.');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _statusLabel(String status) {
    if (status == 'paid' || status == 'verified') {
      return 'Paid';
    }
    if (status == 'submitted') {
      return 'Pending Verification';
    }
    if (status == 'rejected') {
      return 'Rejected';
    }
    return status;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pay Society Bill')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (!widget.firebaseReady)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                    'Firebase config is pending. Payment references are local only.'),
              ),
            ),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Low-Cost Payment Model (No Gateway)'),
                  SizedBox(height: 8),
                  Text('UPI ID: societyname@okaxis'),
                  Text('Bank A/C: XXXX2345 | IFSC: ABCD0001234'),
                  Text(
                      'Transfer bill amount and submit transaction reference below.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text('Open UPI app using deep link in production.')),
              );
            },
            child: const Text('Pay via UPI App'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount Paid (INR)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _txnRefController,
            decoration: const InputDecoration(
              labelText: 'Transaction Reference Number',
              helperText:
                  'Admin verifies this reference against society bank statement.',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _submitPaymentReference,
            child: const Text('Submit Payment Reference'),
          ),
          if (_submitted)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Reference submitted. Payment status will update after admin verification.',
              ),
            ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseAuth.instance.currentUser == null
                ? null
                : FirebaseFirestore.instance
                    .collection('payments')
                    .where('ownerUid',
                        isEqualTo: FirebaseAuth.instance.currentUser!.uid)
                    .orderBy('createdAt', descending: true)
                    .limit(10)
                    .snapshots(),
            builder: (BuildContext context,
                AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot) {
              if (snapshot.hasError) {
                return Text(
                    'Unable to load payment history: ${snapshot.error}');
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Text('No payment submissions yet.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Recent Payment Submissions',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ...snapshot.data!.docs
                      .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
                    final Map<String, dynamic> data = doc.data();
                    final double paid =
                        (data['amount'] as num?)?.toDouble() ?? 0;
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${data['monthKey'] ?? '-'} | INR ${paid.toStringAsFixed(2)}',
                        ),
                        subtitle: Text(
                          'Txn ${data['txnRef'] ?? '-'} | Status: ${_statusLabel((data['status'] ?? 'submitted').toString())}'
                          '${(data['requestedAt'] as Timestamp?) == null ? '' : '\nRequested: ${DateFormat('dd MMM yyyy, hh:mm a').format((data['requestedAt'] as Timestamp).toDate())}'}'
                          '${((data['paidAt'] as Timestamp?) ?? (data['verifiedAt'] as Timestamp?)) == null ? '' : '\nUpdated: ${DateFormat('dd MMM yyyy, hh:mm a').format(((data['paidAt'] as Timestamp?) ?? (data['verifiedAt'] as Timestamp?))!.toDate())}'}',
                        ),
                        isThreeLine: true,
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
