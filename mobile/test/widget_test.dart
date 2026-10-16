import 'package:flutter_test/flutter_test.dart';
import 'package:ev_charging_management/app.dart';

void main() {
  testWidgets('App opens login when firebase not ready', (WidgetTester tester) async {
    await tester.pumpWidget(const EvChargingApp(firebaseReady: false));
    expect(find.textContaining('Firebase setup is incomplete'), findsOneWidget);
  });
}
