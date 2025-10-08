import 'package:flutter_test/flutter_test.dart';
import 'package:messie_app/ui/core/back_esc/back_esc_policy.dart';
import 'package:flutter/widgets.dart';

void main() {
  testWidgets('BackEscPolicy dismisses in correct order', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: BackEscPolicy(
          child: Builder(builder: (context) {
            // Register a route-level surface
            BackEscPolicy.of(context).registerSurface(
              priority: SurfacePriority.route,
              onDismiss: () async {
                calls.add('route');
                return true;
              },
            );
            // Register a modal
            BackEscPolicy.of(context).registerSurface(
              priority: SurfacePriority.modal,
              onDismiss: () async {
                calls.add('modal');
                return true;
              },
            );
            // Register a popup
            BackEscPolicy.of(context).registerSurface(
              priority: SurfacePriority.popup,
              onDismiss: () async {
                calls.add('popup');
                return true;
              },
            );
            return const SizedBox.shrink();
          }),
        ),
      ),
    );

    // 1st back -> popup
    final policy = tester.widget<BackEscPolicy>(find.byType(BackEscPolicy));
    await policy.handleBack();
    // 2nd back -> modal
    await policy.handleBack();
    // 3rd back -> route
    await policy.handleBack();

    expect(calls, ['popup', 'modal', 'route']);
  });
}

