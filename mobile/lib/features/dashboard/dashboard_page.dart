import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../admin/admin_page.dart';
import '../billing/billing_page.dart';
import '../booking/slot_booking_page.dart';
import '../payments/payment_page.dart';
import '../sessions/session_entry_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    required this.firebaseReady,
    this.isAdmin = false,
    super.key,
  });

  static const String routeName = '/dashboard';
  final bool firebaseReady;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Society EV Dashboard'),
        actions: <Widget>[
          IconButton(
            onPressed: () => _showProfileSheet(context),
            icon: const Icon(Icons.account_circle),
          ),
          IconButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (uid.isNotEmpty)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (BuildContext context,
                  AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>>
                      snapshot) {
                final Map<String, dynamic> user =
                    snapshot.data?.data() ?? <String, dynamic>{};
                final String name = (user['name'] ?? '').toString();
                final String role = ((user['role'] ?? '').toString() == 'admin')
                    ? 'Admin'
                    : 'Resident';
                final String flat = (user['flatNumber'] ?? '').toString();
                return Card(
                  child: ListTile(
                    title: Text(
                      name.isEmpty ? 'Welcome' : 'Welcome, $name',
                    ),
                    subtitle: Text(
                      '$role${flat.isEmpty ? '' : ' | Flat: $flat'}',
                    ),
                  ),
                );
              },
            ),
          if (!firebaseReady)
            const Card(
              child: ListTile(
                title: Text('Setup Pending'),
                subtitle: Text('Firebase config is not linked yet.'),
              ),
            ),
          _menuTile(
            context: context,
            title: 'Start/Stop Charging Session',
            subtitle: 'Capture meter values and auto-calculate charge.',
            routeName: SessionEntryPage.routeName,
          ),
          _menuTile(
            context: context,
            title: 'Book Charging Slot',
            subtitle: 'Reserve available charging time slots.',
            routeName: SlotBookingPage.routeName,
          ),
          _menuTile(
            context: context,
            title: 'View Bills',
            subtitle: 'See monthly units consumed and charges.',
            routeName: BillingPage.routeName,
          ),
          _menuTile(
            context: context,
            title: 'Pay Bill (Low-Cost Model)',
            subtitle: 'UPI/bank transfer with transaction reference upload.',
            routeName: PaymentPage.routeName,
          ),
          if (isAdmin)
            _menuTile(
              context: context,
              title: 'Admin Panel',
              subtitle: 'Approve users, manage access and monitor usage.',
              routeName: AdminPage.routeName,
            ),
        ],
      ),
    );
  }

  void _showProfileSheet(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Profile',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(user?.email ?? '-'),
                const SizedBox(height: 8),
                const Text('Use Admin Panel to manage users and rates.'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _menuTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String routeName,
  }) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () => Navigator.pushNamed(context, routeName),
      ),
    );
  }
}
