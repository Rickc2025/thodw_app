import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thodw_aqx/screens/login_screen.dart';

void main() {
  testWidgets('login screen renders Melco login fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('HODW AQX Login'), findsOneWidget);
    expect(find.text('Melco ID'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}
