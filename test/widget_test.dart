import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomin/main.dart';

void main() {
  testWidgets('app uses the Zoomin product name', (tester) async {
    await tester.pumpWidget(
      const ZoominApp(home: Scaffold(body: Text('Zoomin'))),
    );

    expect(find.text('Zoomin'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
