import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:draftroom/auth_dialog.dart';

const emailKey = ValueKey('coach-auth-email');
const passwordKey = ValueKey('coach-auth-password');
const modeKey = ValueKey('coach-auth-mode');
const submitKey = ValueKey('coach-auth-submit');
const cancelKey = ValueKey('coach-auth-cancel');

void main() {
  Future<GlobalKey> open(
    WidgetTester tester,
    CoachAuthenticate authenticate, {
    Size size = const Size(360, 640),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final preview = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: preview,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => CoachAuthDialog(authenticate: authenticate),
                  ),
                  child: const Text('Open account'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open account'));
    await tester.pumpAndSettle();
    return preview;
  }

  Future<void> credentials(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(emailKey));
    await tester.enterText(find.byKey(emailKey), ' coach@example.test ');
    await tester.ensureVisible(find.byKey(passwordKey));
    await tester.enterText(find.byKey(passwordKey), 'test-only-password');
  }

  for (final config in [
    (const Size(320, 568), 280.0, 1.0),
    (const Size(360, 640), 300.0, 1.5),
    (const Size(640, 360), 180.0, 1.0),
  ]) {
    testWidgets(
      'account form survives keyboard, mode switches and closing at ${config.$1}',
      (tester) async {
        final preview = await open(
          tester,
          (email, password, {name}) async {},
          size: config.$1,
          scale: config.$3,
        );
        await credentials(tester);
        tester.view.viewInsets = FakeViewPadding(bottom: config.$2);
        await tester.pumpAndSettle();
        for (var i = 0; i < 3; i++) {
          await tester.ensureVisible(find.byKey(modeKey));
          await tester.tap(find.byKey(modeKey));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(find.byKey(emailKey)).controller!.text,
            ' coach@example.test ',
          );
          expect(
            tester.widget<TextField>(find.byKey(passwordKey)).controller!.text,
            'test-only-password',
          );
          expect(tester.takeException(), isNull);
        }
        expect(find.text('Create coach account'), findsOneWidget);
        expect(find.byKey(cancelKey).hitTestable(), findsOneWidget);
        expect(find.byKey(submitKey).hitTestable(), findsOneWidget);
        if (Platform.environment['DRAFTROOM_CAPTURE_AUTH'] == '1' &&
            config.$1.width == 320) {
          await tester.runAsync(() async {
            final boundary =
                preview.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File(
              'build/auth-dialog-small-screen.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byKey(cancelKey));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(find.byType(CoachAuthDialog), findsNothing);
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = FakeViewPadding.zero;
        await tester.tap(find.text('Open account'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(cancelKey));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('long server errors stay scrollable and retry succeeds', (
    tester,
  ) async {
    var calls = 0;
    final error = List.filled(
      10,
      'Please check your credentials and try again.',
    ).join(' ');
    await open(tester, (email, password, {name}) async {
      expect(email, 'coach@example.test');
      if (++calls == 1) throw Exception(error);
    }, size: const Size(320, 568));
    await credentials(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(submitKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('coach-auth-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(submitKey));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(CoachAuthDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending login prevents duplicate submits and closes safely on success',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await open(tester, (email, password, {name}) {
        calls++;
        return pending.future;
      });
      await credentials(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(submitKey));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byKey(submitKey)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(find.byKey(cancelKey)).onPressed,
        isNull,
      );
      await Navigator.of(
        tester.element(find.byType(CoachAuthDialog)),
      ).maybePop();
      await tester.pumpAndSettle();
      expect(find.byType(CoachAuthDialog), findsOneWidget);
      expect(calls, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CoachAuthDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an auth response after the host is removed does not update disposed state',
    (tester) async {
      final pending = Completer<void>();
      await open(tester, (email, password, {name}) => pending.future);
      await credentials(tester);
      await tester.tap(find.byKey(submitKey));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
