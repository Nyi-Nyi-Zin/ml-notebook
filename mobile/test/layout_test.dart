import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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
}
