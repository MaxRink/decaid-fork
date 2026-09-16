import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/ui/startup_failure_shell.dart';
import 'package:reaprime/src/ui/webserver_port_conflict_app.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('names the port and offers both actions', (tester) async {
    await tester.pumpWidget(
      StartupFailureShell(
        child: WebServerPortConflictScreen(
          port: 8080,
          probe: (_) async => false,
        ),
      ),
    );

    expect(find.text('Another Decaid app is running'), findsOneWidget);
    expect(find.textContaining('Port 8080 is already in use'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
    expect(find.text('Close this app'), findsOneWidget);
  });

  testWidgets('uses Shad presentation', (tester) async {
    await tester.pumpWidget(
      StartupFailureShell(
        child: WebServerPortConflictScreen(
          port: 8080,
          probe: (_) async => false,
        ),
      ),
    );

    expect(find.byType(ShadAlert), findsAtLeastNWidgets(1));
    expect(find.byType(ShadButton), findsNWidgets(2));
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('says the port is still in use when the probe says so', (
    tester,
  ) async {
    await tester.pumpWidget(
      StartupFailureShell(
        child: WebServerPortConflictScreen(
          port: 8080,
          probe: (_) async => false,
        ),
      ),
    );
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();

    expect(find.textContaining('is still in use'), findsOneWidget);
  });

  testWidgets('says the port is free when the probe says so', (tester) async {
    await tester.pumpWidget(
      StartupFailureShell(
        child: WebServerPortConflictScreen(
          port: 8080,
          probe: (_) async => true,
        ),
      ),
    );
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();

    expect(find.textContaining('is free now'), findsOneWidget);
  });

  testWidgets('asks about the port it was given', (tester) async {
    final asked = <int>[];
    await tester.pumpWidget(
      StartupFailureShell(
        child: WebServerPortConflictScreen(
          port: 4001,
          probe: (p) async {
            asked.add(p);
            return false;
          },
        ),
      ),
    );
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();

    expect(asked, [4001]);
  });
}
