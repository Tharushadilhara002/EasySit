import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:easy_sit1212/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const EasySitApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
