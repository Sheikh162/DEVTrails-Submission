import 'package:flutter_test/flutter_test.dart';

import 'package:devtrails_app/main.dart';

void main() {
  testWidgets('app boots smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const VrittiApp());
  });
}
