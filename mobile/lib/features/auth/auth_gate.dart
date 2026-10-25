import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../dashboard/dashboard_page.dart';
import 'login_page.dart';
import 'pending_approval_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({required this.firebaseReady, super.key});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    if (!firebaseReady) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Firebase setup is incomplete. Please check Firebase config files.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (BuildContext context, AsyncSnapshot<User?> authSnap) {
        if (!authSnap.hasData) {
          return const LoginPage();
        }
        final User user = authSnap.data!;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (BuildContext context,
              AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>>
                  profileSnap) {
            if (profileSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (profileSnap.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Profile load failed: ${profileSnap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            final Map<String, dynamic> data =
                profileSnap.data?.data() ?? <String, dynamic>{};
            final String status = (data['status'] ?? 'active').toString();
            if (status == 'disabled') {
              return PendingApprovalPage(
                email: user.email ?? '',
                status: status,
              );
            }
            final bool isAdmin = (data['role'] ?? '') == 'admin';
            return DashboardPage(
              firebaseReady: firebaseReady,
              isAdmin: isAdmin,
            );
          },
        );
      },
    );
  }
}
