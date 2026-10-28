import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/flat_billing.dart';
import '../../core/flat_payment_linker.dart';
import '../../core/flat_session_merge.dart';
import '../admin/admin_page.dart';
import '../billing/billing_page.dart';
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
          if (uid.isNotEmpty && firebaseReady) _homeSnapshot(uid),
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
            title: 'View Bills',
            subtitle: 'See monthly units consumed and charges.',
            routeName: BillingPage.routeName,
          ),
          if (isAdmin)
            _menuTile(
              context: context,
              title: 'Admin Panel',
              subtitle: 'Approve users, manage access and monitor usage.',
              routeName: AdminPage.routeName,
            ),
          if (firebaseReady) _liveChargingStatusCard(),
        ],
      ),
    );
  }

  Widget _homeSnapshot(String uid) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (BuildContext context,
          AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> userSnap) {
        final Map<String, dynamic>? userData = userSnap.data?.data();
        final FlatProfileScope? scope = FlatProfileScope.fromUser(userData);
        if (scope != null) {
          FlatPaymentLinker.ensureOwn(uid, scope);
          FlatPaymentLinker.ensureOwnSessions(uid, scope);
        }
        return FlatSessionMerge(
          uid: uid,
          scope: scope,
          builder: (List<QueryDocumentSnapshot<Map<String, dynamic>>>
              loadedSessions) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('payments')
                  .where('ownerUid', isEqualTo: uid)
                  .snapshots(),
              builder: (BuildContext context,
                  AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>
                      ownPaySnap) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: scope == null
                      ? null
                      : FirebaseFirestore.instance
                          .collection('payments')
                          .where('billingFlatKey', isEqualTo: scope.key)
                          .snapshots(),
                  builder: (BuildContext context,
                      AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>
                          flatPaySnap) {
                    if (ownPaySnap.hasError || flatPaySnap.hasError) {
                      return const Card(
                        child: ListTile(
                          title: Text('Usage snapshot unavailable'),
                          subtitle:
                              Text('Could not load dues and consumption.'),
                        ),
                      );
                    }
                    if (!ownPaySnap.hasData ||
                        (scope != null && !flatPaySnap.hasData)) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      );
                    }
                    final Map<String, Map<String, dynamic>> paymentData =
                        FlatBillMath.dedupePayments(<MapEntry<String,
                            Map<String, dynamic>>>[
                      ...ownPaySnap.data!.docs.map(
                        (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                            MapEntry<String, Map<String, dynamic>>(
                                doc.id, doc.data()),
                      ),
                      ...?flatPaySnap.data?.docs.map(
                        (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                            MapEntry<String, Map<String, dynamic>>(
                                doc.id, doc.data()),
                      ),
                    ]);
                    final FlatBillTotals totals = FlatBillMath.summarize(
                      sessions: loadedSessions.map(
                          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                              doc.data()),
                      payments: paymentData.values,
                      scope: scope,
                      viewerUid: uid,
                    );
                    final double units = totals.units;
                    final double billed = totals.billed;
                    final double paid = totals.paid;
                    final double due = totals.due;
                    final double paidRatio =
                        billed <= 0 ? 1 : (paid / billed).clamp(0, 1);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            colors: <Color>[
                              Color(0xFF0F766E),
                              Color(0xFF115E59)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Your charging snapshot',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              scope == null
                                  ? 'Total usage and outstanding amount'
                                  : 'Combined for flat ${scope.wing}-${scope.flat}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: _GraphMetric(
                                    title: 'Total Consumption',
                                    value: '${units.toStringAsFixed(1)} kWh',
                                    caption: 'Completed sessions',
                                    progress: units <= 0 ? 0.08 : 0.78,
                                    color: const Color(0xFF5EEAD4),
                                    icon: Icons.bolt,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _GraphMetric(
                                    title: 'Total Dues',
                                    value: 'INR ${due.toStringAsFixed(0)}',
                                    caption: due <= 0
                                        ? 'All clear'
                                        : 'Paid ${(paidRatio * 100).toStringAsFixed(0)}%',
                                    progress: due <= 0 ? 1 : (1 - paidRatio),
                                    color: due <= 0
                                        ? const Color(0xFF86EFAC)
                                        : const Color(0xFFFDBA74),
                                    icon: Icons.account_balance_wallet,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const _PublishedVersionBanner(),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
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

  Widget _liveChargingStatusCard() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chargingSlots')
          .where('occupied', isEqualTo: true)
          .snapshots(),
      builder: (BuildContext context,
          AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: ListTile(
              title: Text('Current Charging Status'),
              subtitle: Text('Loading active slots...'),
            ),
          );
        }
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
            snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Card(
            child: ListTile(
              title: Text('Current Charging Status'),
              subtitle: Text('All charging points are currently available.'),
            ),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Current Charging Status',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ...docs.map((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
                  final Map<String, dynamic> data = doc.data();
                  final DateTime? startedAt =
                      (data['startedAt'] as Timestamp?)?.toDate();
                  final String sinceText = startedAt == null
                      ? '-'
                      : DateFormat('dd MMM, hh:mm a').format(startedAt);
                  final String resident =
                      (data['residentName'] ?? '-').toString();
                  final String flat = (data['flatNumber'] ?? '-').toString();
                  final String vehicle =
                      (data['vehicleNumber'] ?? '-').toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${doc.id}: $vehicle | $resident ($flat) | Since $sinceText',
                    ),
                  );
                }),
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

class _GraphMetric extends StatelessWidget {
  const _GraphMetric({
    required this.title,
    required this.value,
    required this.caption,
    required this.progress,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final String caption;
  final double progress;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            width: 78,
            height: 78,
            child: CustomPaint(
              painter: _RingPainter(progress: progress, color: color),
              child: Center(
                child: Icon(icon, color: color, size: 22),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) / 2 - 6;
    final Paint track = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final Paint arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _PublishedVersionBanner extends StatelessWidget {
  const _PublishedVersionBanner();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (BuildContext context, AsyncSnapshot<PackageInfo> packageSnap) {
        final String installed = packageSnap.data?.version ?? '-';
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('appConfig')
              .doc('appVersion')
              .snapshots(),
          builder: (BuildContext context,
              AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot) {
            final String published = ((snapshot.data?.data() ??
                        <String, dynamic>{})['currentVersion'] ??
                    '')
                .toString();
            final String shown =
                published.isEmpty ? 'Not published yet' : published;
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'App version: $shown\nInstalled on this phone: $installed',
                style: const TextStyle(color: Colors.white, height: 1.35),
              ),
            );
          },
        );
      },
    );
  }
}
