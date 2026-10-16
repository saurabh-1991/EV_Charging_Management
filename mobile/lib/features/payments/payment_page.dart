import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

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
    final String txnRef = _txnRefController.text.trim().toUpperCase();
    final double amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (uid.isEmpty) {
      _toast('Please login first.');
      return;
    }
    if (txnRef.isEmpty || amount <= 0) {
      _toast('Enter valid amount and transaction reference.');
      return;
    }
    final String monthKey = DateFormat('yyyy-MM').format(DateTime.now());
    final QuerySnapshot<Map<String, dynamic>> existing = await FirebaseFirestore
        .instance
        .collection('payments')
        .where('ownerUid', isEqualTo: uid)
        .where('monthKey', isEqualTo: monthKey)
        .where('status', isEqualTo: 'submitted')
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      _toast('A payment reference is already pending for this month.');
      return;
    }
    final QuerySnapshot<Map<String, dynamic>> duplicateTxn =
        await FirebaseFirestore.instance
            .collection('payments')
            .where('ownerUid', isEqualTo: uid)
            .where('monthKey', isEqualTo: monthKey)
            .where('txnRef', isEqualTo: txnRef)
            .limit(1)
            .get();
    if (duplicateTxn.docs.isNotEmpty) {
      _toast('This transaction reference already exists for this month.');
      return;
    }
    await FirebaseFirestore.instance
        .collection('payments')
        .add(<String, dynamic>{
      'ownerUid': uid,
      'txnRef': txnRef,
      'amount': amount,
      'monthKey': monthKey,
      'status': 'submitted',
      'createdAt': FieldValue.serverTimestamp(),
    });
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
                          'Txn ${data['txnRef'] ?? '-'} | Status: ${data['status'] ?? 'submitted'}',
                        ),
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
