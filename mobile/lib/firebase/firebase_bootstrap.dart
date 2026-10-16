import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

class FirebaseBootstrap {
  static String? lastError;

  static Future<bool> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }
}
