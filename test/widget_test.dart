import 'package:aloud/core/ui/widgets.dart';
import 'package:aloud/features/lock/lock_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('EmptyState shows its title and message', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: EmptyState(icon: Icons.inbox, title: 'Nothing here', message: 'Add something')),
    ));
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Add something'), findsOneWidget);
  });

  testWidgets('LockScreen reports a wrong passphrase and stays locked', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      home: LockScreen(onSubmit: (pass) async {
        attempts++;
        return false;
      }),
    ));
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.text('That passphrase is not correct.'), findsOneWidget);
  });

  testWidgets('SliderTile reports changes', (tester) async {
    double value = 0.5;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SliderTile(
            title: 'Speed',
            value: value,
            min: 0,
            max: 1,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    ));
    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pump();
    expect(value > 0.5, isTrue);
  });
}
