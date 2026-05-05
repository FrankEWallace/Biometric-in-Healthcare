import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_system/providers/theme_provider.dart';
import 'package:biometric_system/main.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    final theme = ThemeProvider();
    await tester.pumpWidget(BiometricApp(themeProvider: theme));
    expect(find.byType(BiometricApp), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
