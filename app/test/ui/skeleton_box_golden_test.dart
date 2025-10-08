import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:messie_app/theme/app_theme.dart';
import 'package:messie_app/ui/components/skeleton/skeleton_box.dart';

void main() {
  testWidgets('SkeletonBox golden', (tester) async {
    final widget = MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: Center(
          child: SkeletonBox(width: 120, height: 16),
        ),
      ),
    );
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SkeletonBox),
      matchesGoldenFile('goldens/skeleton_box_light.png'),
    );
  // Baseline needs generation via `flutter test --update-goldens`.
  }, skip: true);
}
