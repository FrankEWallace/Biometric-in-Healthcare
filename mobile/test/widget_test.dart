import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_system/main.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BiometricApp());
    expect(find.byType(BiometricApp), findsOneWidget);
  });
}
