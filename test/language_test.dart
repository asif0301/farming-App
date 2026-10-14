import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naveedcattlefarm/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
