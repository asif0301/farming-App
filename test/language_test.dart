import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naveedcattlefarm/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'new database is empty and records can be added, edited and deleted',
    () async {
      final directory = await Directory.systemTemp.createTemp('farm-crud-');
      final file = '${directory.path}/farm.sqlite';
      try {
        await Store.instance.open(databasePath: file);
        for (final table in [
          'animals',
          'feed_purchases',
          'feed_consumption',
          'weights',
          'sales',
          'expenses',
          'health',
        ]) {
          expect(await Store.instance.all(table), isEmpty, reason: table);
        }

        final id = await Store.instance.add('animals', {
          'tag': 'USER-1',
          'breed': 'Sahiwal',
          'purchase_date': '2026-10-14',
          'purchase_weight': 300,
          'purchase_price': 150000,
          'current_weight': 300,
          'seller': 'User seller',
          'status': 'Farm par',
        });
        await Store.instance.update('animals', id, {
          'tag': 'USER-1',
          'breed': 'Cholistani',
          'purchase_date': '2026-10-14',
          'purchase_weight': 300,
          'purchase_price': 150000,
          'current_weight': 315,
          'seller': 'User seller',
          'status': 'Farm par',
        });
        expect(
          (await Store.instance.all('animals')).single['breed'],
          'Cholistani',
        );
        await Store.instance.remove('animals', id);
        expect(await Store.instance.all('animals'), isEmpty);
        await Store.instance.db.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('v2 migration removes demo rows but preserves user records', () async {
    final directory = await Directory.systemTemp.createTemp('farm-cleanup-');
    final file = '${directory.path}/farm.sqlite';
    try {
      await Store.instance.open(databasePath: file);
      await Store.instance.add('animals', {
        'tag': 'NF-001',
        'breed': 'Sahiwal',
        'seller': 'Ali Livestock Market',
      });
      await Store.instance.add('animals', {
        'tag': 'MY-001',
        'breed': 'Sahiwal',
        'seller': 'My seller',
      });
      await Store.instance.db.setVersion(2);
      await Store.instance.db.close();

      await Store.instance.open(databasePath: file);
      final animals = await Store.instance.all('animals');
      expect(animals.map((row) => row['tag']), ['MY-001']);
      await Store.instance.db.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'v1 upgrade preserves animals and language survives reopening',
    () async {
      final directory = await Directory.systemTemp.createTemp('farm-language-');
      final file = '${directory.path}/farm.sqlite';
      try {
        await Store.instance.open(databasePath: file);
        final before = await Store.instance.all('animals');
        await Store.instance.db.execute('DROP TABLE settings');
        await Store.instance.db.setVersion(1);
        await Store.instance.db.close();

        await Store.instance.open(databasePath: file);
        await loadLanguage();
        expect(appLocale.value, const Locale('en'));
        expect(await Store.instance.all('animals'), before);
        await changeLanguage('ur');
        expect(appLocale.value, const Locale('ur'));
        await Store.instance.db.close();
        appLocale.value = const Locale('en');
        await Store.instance.open(databasePath: file);
        await loadLanguage();
        expect(appLocale.value, const Locale('ur'));
        await changeLanguage('en');
        await loadLanguage();
        expect(appLocale.value, const Locale('en'));
        expect(await Store.instance.all('animals'), before);
        await Store.instance.db.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
