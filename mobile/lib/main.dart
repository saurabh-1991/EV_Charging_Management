import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bool firebaseReady = await FirebaseBootstrap.initialize();
  runApp(EvChargingApp(firebaseReady: firebaseReady));
}
