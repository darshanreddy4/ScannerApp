import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/monetization/data/admob_service.dart';

void main() {
  testWidgets('typing is detected while a text field has focus or the keyboard is up', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(focusNode: focus)),
      ),
    );
    expect(isTyping(), isFalse);

    focus.requestFocus();
    await tester.pump();
    expect(isTyping(), isTrue);

    focus.unfocus();
    await tester.pump();
    expect(isTyping(), isFalse);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    expect(isTyping(), isTrue);
  });
}
