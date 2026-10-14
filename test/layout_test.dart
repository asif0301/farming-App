import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:naveedcattlefarm/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naveedcattlefarm/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Store.instance.open(databasePath: inMemoryDatabasePath);
    final records = <String, List<Map<String, Object?>>>{};
    for (final table in [
      'animals',
      'feed_purchases',
      'sales',
      'expenses',
      'health',
    ]) {
      records[table] = await Store.instance.all(table);
    }
    await Store.instance.db.close();
    Store.instance.db = LayoutDatabase(records);
  });

  testWidgets('language menu switches the whole app in both directions', (
    tester,
  ) async {
    appLocale.value = const Locale('en');
    addTearDown(() => appLocale.value = const Locale('en'));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اردو'));
    await tester.pumpAndSettle();
    expect(find.text('آپ کے فارم کا خلاصہ'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(AppBar))),
      TextDirection.rtl,
    );
    expect(appLocale.value.languageCode, 'ur');
    expect((await Store.instance.db.query('settings')).first['value'], 'ur');
    await tester.tap(find.byKey(const ValueKey('language-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Your farm, at a glance'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(AppBar))),
      TextDirection.ltr,
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'ur']) {
    for (final size in [
      const Size(320, 640),
      const Size(390, 844),
      const Size(640, 360),
      const Size(800, 1024),
      const Size(1024, 400),
      const Size(1440, 900),
    ]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets(
          '$language all screens at ${size.width}x${size.height}, text $scale',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(language),
                supportedLocales: const [Locale('en'), Locale('ur')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const Shell(),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            for (var i = 1; i < nav.length; i++) {
              if (size.width < 900) {
                tester
                    .state<ScaffoldState>(find.byType(Scaffold).first)
                    .openDrawer();
                await tester.pumpAndSettle();
              }
              final tile = find.byKey(ValueKey('menu-$i'));
              await tester.scrollUntilVisible(
                tile,
                100,
                scrollable: find.descendant(
                  of: find.byKey(const ValueKey('navigation-list')),
                  matching: find.byType(Scrollable),
                ),
              );
              await tester.pumpAndSettle();
              await tester.tap(tile);
              await tester.pumpAndSettle();
              expect(find.byType(AppBar), findsOneWidget);
              expect(
                Directionality.of(tester.element(find.byType(AppBar))),
                language == 'ur' ? TextDirection.rtl : TextDirection.ltr,
              );
              expect(
                find.descendant(
                  of: find.byType(AppBar),
                  matching: find.text(
                    language == 'ur' ? urduStrings[nav[i].$1]! : nav[i].$1,
                  ),
                ),
                findsOneWidget,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: 'screen ${nav[i].$1}',
              );
            }
          },
        );
      }
    }

    for (final size in [const Size(320, 640), const Size(640, 360)]) {
      testWidgets('$language record dialogs with keyboard at $size', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final labels in [
          [
            'Tag / ID',
            'Breed',
            'Purchase weight kg',
            'Purchase price Rs',
            'Market / seller',
          ],
          ['Feed type', 'Quantity kg', 'Rate / kg', 'Supplier'],
          [
            'Factory name',
            'Animal ID',
            'Sale weight kg',
            'Rate / kg',
            'Payment received',
          ],
          ['Category', 'Description', 'Amount Rs'],
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('en'), Locale('ur')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => formDialog(
                      context,
                      'Add record',
                      'animals',
                      labels,
                      (_) => {},
                      () {},
                    ),
                    child: const Text('Open form'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open form'));
          await tester.pumpAndSettle();
          tester.view.viewInsets = FakeViewPadding(
            bottom: size.height < 400 ? 160 : 300,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(
            find.text(language == 'ur' ? 'منسوخ کریں' : 'Cancel'),
          );
          await tester.tap(
            find.text(language == 'ur' ? 'منسوخ کریں' : 'Cancel'),
          );
          await tester.pumpAndSettle();
          tester.view.resetViewInsets();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}

// Keep native database I/O out of the widget test's simulated clock.
// Records are loaded from the real SQLite schema in setUpAll.
class LayoutDatabase implements Database {
  final Map<String, List<Map<String, Object?>>> records;
  LayoutDatabase(this.records);
  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    records[table] = [Map.of(values)];
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async => records[table] ?? [];
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => [
    {'value': 123456.78},
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
