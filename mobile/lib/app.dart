import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'features/admin/admin_page.dart';
import 'features/auth/auth_gate.dart';
import 'features/billing/billing_page.dart';
import 'features/booking/slot_booking_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/payments/payment_page.dart';
import 'features/sessions/session_entry_page.dart';

class EvChargingApp extends StatelessWidget {
  const EvChargingApp({required this.firebaseReady, super.key});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Society EV Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      scrollBehavior: const _AppScrollBehavior(),
      home: AuthGate(firebaseReady: firebaseReady),
      routes: <String, WidgetBuilder>{
        DashboardPage.routeName: (_) =>
            DashboardPage(firebaseReady: firebaseReady),
        SessionEntryPage.routeName: (_) =>
            SessionEntryPage(firebaseReady: firebaseReady),
        SlotBookingPage.routeName: (_) => const SlotBookingPage(),
        BillingPage.routeName: (_) => const BillingPage(),
        PaymentPage.routeName: (_) => PaymentPage(firebaseReady: firebaseReady),
        AdminPage.routeName: (_) => const AdminPage(),
      },
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}
