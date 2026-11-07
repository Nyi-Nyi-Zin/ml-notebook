import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:draftroom/auth_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:draftroom/main.dart';
import 'package:draftroom/models.dart';
import 'package:draftroom/workspace.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  for (final width in [390.0, 1440.0]) {
    testWidgets('draft layout at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = Workspace();
      w.catalog = Catalog.fromJson(
        jsonDecode(File('assets/catalog.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      w.draft = Draft.sample(w.catalog!.id);
      w.loading = false;
      w.refreshAnalysis();
      await tester.pumpWidget(DraftRoomApp(workspace: w, initialize: false));
      await tester.pumpAndSettle();
      expect(find.text('Your next winning draft.'), findsOneWidget);
      expect(find.text('Minotaur'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Matchup'));
      await tester.tap(find.text('Matchup'));
      await tester.pumpAndSettle();
      expect(find.text('Track copied ultimate'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'account dialog integrates with the app while the keyboard is open',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final w = Workspace();
      w.api.baseUrl = 'https://api.example.test';
      w.catalog = Catalog.fromJson(
        jsonDecode(File('assets/catalog.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      w.draft = Draft.sample(w.catalog!.id);
      w.loading = false;
      w.refreshAnalysis();
      await tester.pumpWidget(DraftRoomApp(workspace: w, initialize: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sign in'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('coach-auth-email')),
        'coach@example.test',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('coach-auth-mode')));
      await tester.tap(find.byKey(const ValueKey('coach-auth-mode')));
      await tester.pumpAndSettle();
      expect(find.text('Create coach account'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('coach-auth-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(CoachAuthDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
