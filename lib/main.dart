import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile_sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final appLocale = ValueNotifier<Locale>(const Locale('en'));

Future<void> loadLanguage() async {
  final rows = await Store.instance.db.query(
    'settings',
    where: 'key = ?',
    whereArgs: ['language'],
  );
  appLocale.value = Locale(
    rows.isNotEmpty && rows.first['value'] == 'ur' ? 'ur' : 'en',
  );
}

Future<void> changeLanguage(String code) async {
  if (!['en', 'ur'].contains(code)) return;
  await Store.instance.db.insert('settings', {
    'key': 'language',
    'value': code,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  appLocale.value = Locale(code);
}

String day() => DateTime.now().toIso8601String().substring(0, 10);
String cash(num n) => 'Rs ${n.toStringAsFixed(0)}';

class Store {
  Store._();
  static final instance = Store._();
  late Database db;
  Future<void> open({String? databasePath}) async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    } else if (!kIsWeb) {
      databaseFactory = mobile_sqflite.databaseFactory;
    }
    final location =
        databasePath ??
        path.join(
          (await getApplicationDocumentsDirectory()).path,
          'naveed_cattle_farm.sqlite',
        );
    db = await openDatabase(
      location,
      version: 3,
      onUpgrade: (d, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await d.execute(
            'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        }
        if (oldVersion < 3) await _removeDemoData(d);
      },
      onCreate: (d, _) async {
        for (final sql in [
          'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          'CREATE TABLE animals(id INTEGER PRIMARY KEY AUTOINCREMENT, tag TEXT UNIQUE, breed TEXT, purchase_date TEXT, purchase_weight REAL, purchase_price REAL, current_weight REAL, seller TEXT, status TEXT)',
          'CREATE TABLE feed_purchases(id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, quantity REAL, rate REAL, supplier TEXT, date TEXT, paid REAL)',
          'CREATE TABLE feed_consumption(id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, quantity REAL, wastage REAL, date TEXT, animal_tag TEXT)',
          'CREATE TABLE weights(id INTEGER PRIMARY KEY AUTOINCREMENT, animal_id TEXT, weight REAL, date TEXT)',
          'CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT, animal_id TEXT, factory TEXT, date TEXT, weight REAL, rate REAL, total REAL, transport REAL, commission REAL, received REAL)',
          'CREATE TABLE expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, category TEXT, description TEXT, amount REAL, date TEXT, kind TEXT)',
          'CREATE TABLE health(id INTEGER PRIMARY KEY AUTOINCREMENT, animal_id TEXT, type TEXT, notes TEXT, cost REAL, date TEXT, doctor TEXT)',
        ]) {
          await d.execute(sql);
        }
      },
    );
  }

  static Future<void> _removeDemoData(Database d) async {
    await d.delete(
      'animals',
      where:
          "(tag = 'NF-001' AND seller = 'Ali Livestock Market') OR "
          "(tag = 'NF-002' AND seller = 'Raza Farms') OR "
          "(tag = 'NF-003' AND seller = 'Khan Cattle Market')",
    );
    await d.delete(
      'feed_purchases',
      where:
          "(supplier = 'Green Feed Suppliers' AND date = '2026-10-01') OR "
          "(supplier = 'Naveed Wanda Mills' AND date = '2026-10-03') OR "
          "(supplier = 'Punjab Feed House' AND date = '2026-10-04')",
    );
    await d.delete(
      'feed_consumption',
      where: "animal_tag = 'Group A' AND type IN ('Silage','Wanda','Chokar')",
    );
    await d.delete(
      'expenses',
      where:
          "(description = 'Monthly staff salary' AND amount = 45000) OR "
          "(description = 'Routine checkup' AND amount = 6500)",
    );
  }

  Future<List<Map<String, Object?>>> all(String table) =>
      db.query(table, orderBy: 'id DESC');
  Future<int> add(String table, Map<String, Object?> values) async {
    final id = await db.insert(table, values);
    if (table == 'weights') await _syncAnimalWeight('${values['animal_id']}');
    return id;
  }

  Future<int> update(String table, int id, Map<String, Object?> values) async {
    String? previousAnimal;
    if (table == 'weights') {
      final old = await db.query('weights', where: 'id = ?', whereArgs: [id]);
      if (old.isNotEmpty) previousAnimal = '${old.first['animal_id']}';
    }
    final count = await db.update(
      table,
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (table == 'weights') {
      if (previousAnimal != null) await _syncAnimalWeight(previousAnimal);
      await _syncAnimalWeight('${values['animal_id']}');
    }
    return count;
  }

  Future<int> remove(String table, int id) async {
    String? animal;
    if (table == 'weights') {
      final old = await db.query('weights', where: 'id = ?', whereArgs: [id]);
      if (old.isNotEmpty) animal = '${old.first['animal_id']}';
    }
    final count = await db.delete(table, where: 'id = ?', whereArgs: [id]);
    if (animal != null) await _syncAnimalWeight(animal);
    return count;
  }

  Future<void> _syncAnimalWeight(String tag) async {
    final latest = await db.query(
      'weights',
      where: 'animal_id = ?',
      whereArgs: [tag],
      orderBy: 'date DESC, id DESC',
      limit: 1,
    );
    if (latest.isNotEmpty) {
      await db.update(
        'animals',
        {'current_weight': latest.first['weight']},
        where: 'tag = ?',
        whereArgs: [tag],
      );
      return;
    }
    await db.rawUpdate(
      'UPDATE animals SET current_weight = purchase_weight WHERE tag = ?',
      [tag],
    );
  }

  Future<double> total(String sql) async {
    final r = await db.rawQuery(sql);
    return ((r.first.values.first as num?) ?? 0).toDouble();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.instance.open();
  await loadLanguage();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => ValueListenableBuilder<Locale>(
    valueListenable: appLocale,
    builder: (context, locale, _) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ur')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      title: 'Naveed Cattle Farm',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0d7c66)),
        scaffoldBackgroundColor: const Color(0xfff4f7f5),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xff143b34),
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xfff4f7f5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xffdce6df)),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Color(0xffdceee4),
        ),
      ),
      home: const Shell(),
    ),
  );
}

class MyApp extends App {
  const MyApp({super.key});
}

const nav = [
  ('Dashboard', Icons.space_dashboard_outlined),
  ('Animals', Icons.pets_outlined),
  ('Feed & Stock', Icons.inventory_2_outlined),
  ('Weight & Growth', Icons.monitor_weight_outlined),
  ('Factory Sales', Icons.sell_outlined),
  ('Expenses & Accounts', Icons.account_balance_wallet_outlined),
  ('Health & Treatment', Icons.medical_services_outlined),
  ('Reports', Icons.bar_chart_outlined),
  ('Profile', Icons.person_outline),
];

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int selected = 0, refresh = 0;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  void reload() => setState(() => refresh++);
  @override
  Widget build(BuildContext c) {
    final pages = [
      Dashboard(
        open: (i) => setState(() => selected = i),
        key: ValueKey(refresh),
      ),
      Animals(changed: reload, key: ValueKey('a$refresh')),
      Feed(changed: reload, key: ValueKey('f$refresh')),
      Growth(changed: reload, key: ValueKey('g$refresh')),
      Sales(changed: reload, key: ValueKey('s$refresh')),
      Expenses(changed: reload, key: ValueKey('e$refresh')),
      Health(changed: reload, key: ValueKey('h$refresh')),
      Reports(key: ValueKey('r$refresh')),
      const ProfileScreen(),
    ];
    final wide = MediaQuery.sizeOf(c).width >= 900;
    return Scaffold(
      key: scaffoldKey,
      drawer: wide ? null : _mobileDrawer(),
      appBar: AppBar(
        title: AppText(
          nav[selected].$1,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('language-switch'),
            tooltip: translate(c, 'Language'),
            icon: const Icon(Icons.language_outlined),
            onSelected: (code) async {
              try {
                await changeLanguage(code);
              } catch (_) {
                if (c.mounted) {
                  ScaffoldMessenger.of(c).showSnackBar(
                    SnackBar(
                      content: AppText(
                        'Could not save language. Please try again.',
                      ),
                    ),
                  );
                }
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'en',
                checked: appLocale.value.languageCode == 'en',
                child: const Text('English'),
              ),
              CheckedPopupMenuItem(
                value: 'ur',
                checked: appLocale.value.languageCode == 'ur',
                child: const Text('اردو'),
              ),
            ],
          ),
        ],
      ),
      body: Row(
        children: [
          if (wide) _sidebar(),
          Expanded(child: SafeArea(top: false, child: pages[selected])),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _mobileIndex(),
              onDestinationSelected: (index) {
                const targets = [0, 1, 2, 4, 8];
                setState(() => selected = targets[index]);
              },
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: translate(c, 'Home'),
                ),
                NavigationDestination(
                  icon: Icon(Icons.pets_outlined),
                  selectedIcon: Icon(Icons.pets),
                  label: translate(c, 'Animals'),
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2),
                  label: translate(c, 'Feed'),
                ),
                NavigationDestination(
                  icon: Icon(Icons.sell_outlined),
                  selectedIcon: Icon(Icons.sell),
                  label: translate(c, 'Sales'),
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: translate(c, 'Profile'),
                ),
              ],
            ),
    );
  }

  int _mobileIndex() {
    const targets = [0, 1, 2, 4, 8];
    final index = targets.indexOf(selected);
    return index < 0 ? 0 : index;
  }

  Widget _sidebar() => SizedBox(width: 248, child: _menu(false));

  Widget _mobileDrawer() => Drawer(
    backgroundColor: const Color(0xff103b35),
    child: SafeArea(child: _menu(true)),
  );

  Widget _menu(bool closeOnSelect) => Material(
    color: const Color(0xff103b35),
    child: ListView(
      key: const ValueKey('navigation-list'),
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.agriculture_rounded,
                size: 36,
                color: Color(0xffd6f36b),
              ),
              SizedBox(height: 12),
              AppText(
                'NAVEED CATTLE FARM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 4),
              AppText(
                'Farm operations',
                style: TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
        ...nav.asMap().entries.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              key: ValueKey('menu-${e.key}'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              selected: selected == e.key,
              selectedTileColor: const Color(0xff1c5a4e),
              leading: Icon(
                e.value.$2,
                color: selected == e.key
                    ? const Color(0xffd6f36b)
                    : Colors.white60,
              ),
              title: AppText(
                e.value.$1,
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                setState(() => selected = e.key);
                if (closeOnSelect) scaffoldKey.currentState?.closeDrawer();
              },
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: AppText(
            'Your records, always at hand.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class Frame extends StatelessWidget {
  final String title, subtitle;
  final Widget child;
  final Widget? action;
  const Frame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final heading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  title,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: Color(0xff143b34),
                  ),
                ),
                const SizedBox(height: 5),
                AppText(
                  subtitle,
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            );
            if (action == null || constraints.maxWidth > 780) {
              return Row(
                children: [
                  Expanded(child: heading),
                  ...?(action == null
                      ? null
                      : [const SizedBox(width: 16), action!]),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: action!),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        child,
      ],
    ),
  );
}

class CardKpi extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const CardKpi({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xffe0e8e2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: color.withValues(alpha: .1),
          child: Icon(icon, color: color),
        ),
        const SizedBox(height: 16),
        AppText(label, style: const TextStyle(color: Color(0xff63746c))),
        const SizedBox(height: 6),
        AppText(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xff143b34),
          ),
        ),
      ],
    ),
  );
}

class Dashboard extends StatelessWidget {
  final void Function(int) open;
  const Dashboard({super.key, required this.open});

  Future<List<double>> _summary() async {
    final store = Store.instance;
    return Future.wait([
      store.total(
        "SELECT COUNT(*) FROM animals WHERE status IN ('Farm par','Sick')",
      ),
      store.total('SELECT SUM(purchase_price) FROM animals'),
      store.total(
        "SELECT SUM((c.quantity + COALESCE(c.wastage,0)) * COALESCE((SELECT SUM(p.quantity*p.rate)/NULLIF(SUM(p.quantity),0) FROM feed_purchases p WHERE p.type=c.type),0)) FROM feed_consumption c WHERE c.date='${day()}'",
      ),
      store.total(
        'SELECT (SELECT COALESCE(SUM(quantity),0) FROM feed_purchases) - (SELECT COALESCE(SUM(quantity+COALESCE(wastage,0)),0) FROM feed_consumption)',
      ),
      store.total('SELECT SUM(total) FROM sales'),
      store.total('SELECT SUM(total-COALESCE(received,0)) FROM sales'),
      store.total("SELECT SUM(amount) FROM expenses WHERE kind='paid'"),
    ]);
  }

  @override
  Widget build(BuildContext context) => Frame(
    title: 'Rana Naveed Cattle Farm',
    subtitle: 'A clear view of livestock, feed and daily operations.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DashboardOwnerBanner(),
        const SizedBox(height: 24),
        FutureBuilder<List<double>>(
          future: _summary(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const AppText(
                'Unable to load the overview. Please reopen this screen.',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final v = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, size) {
                    final columns = size.maxWidth >= 1050
                        ? 4
                        : size.maxWidth >= 550
                        ? 2
                        : 1;
                    final width =
                        (size.maxWidth - (columns - 1) * 16) / columns;
                    final cards = [
                      CardKpi(
                        label: 'Animals on farm',
                        value: '${v[0].toInt()} head',
                        icon: Icons.pets,
                        color: const Color(0xff0d7c66),
                      ),
                      CardKpi(
                        label: 'Purchase investment',
                        value: cash(v[1]),
                        icon: Icons.payments_outlined,
                        color: Colors.indigo,
                      ),
                      CardKpi(
                        label: 'Today’s feed cost',
                        value: cash(v[2]),
                        icon: Icons.grass,
                        color: const Color(0xffa96a19),
                      ),
                      CardKpi(
                        label: 'Available feed',
                        value: '${v[3].toStringAsFixed(1)} kg',
                        icon: Icons.inventory_2_outlined,
                        color: Colors.deepPurple,
                      ),
                    ];
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: cards
                          .map((card) => SizedBox(width: width, child: card))
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xff103b35),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppText(
                        'Accounts snapshot',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, size) => Wrap(
                          spacing: 20,
                          runSpacing: 20,
                          children:
                              [
                                    ('Factory sales', cash(v[4])),
                                    ('Outstanding sales', cash(v[5])),
                                    ('Recorded expenses', cash(v[6])),
                                  ]
                                  .map(
                                    (item) => SizedBox(
                                      width: size.maxWidth >= 700
                                          ? (size.maxWidth - 40) / 3
                                          : size.maxWidth,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          AppText(
                                            item.$1,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          AppText(
                                            item.$2,
                                            style: const TextStyle(
                                              color: Color(0xffd6f36b),
                                              fontSize: 24,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const AppText(
                  'Quick actions',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => open(1),
                      icon: const Icon(Icons.pets),
                      label: const AppText('Manage animals'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => open(2),
                      icon: const Icon(Icons.grass),
                      label: const AppText('Feed purchases'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => open(4),
                      icon: const Icon(Icons.sell_outlined),
                      label: const AppText('Factory sales'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => open(5),
                      icon: const Icon(Icons.payments_outlined),
                      label: const AppText('Expenses'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class DashboardOwnerBanner extends StatefulWidget {
  const DashboardOwnerBanner({super.key});

  @override
  State<DashboardOwnerBanner> createState() => _DashboardOwnerBannerState();
}

class _DashboardOwnerBannerState extends State<DashboardOwnerBanner> {
  static const images = [
    'assets/banner1.jpg',
    'assets/banner2.jpg',
    'assets/banner3.jpg',
  ];
  final controller = PageController();
  Timer? slideTimer;
  int current = 0;

  @override
  void initState() {
    super.initState();
    slideTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !controller.hasClients) return;
      final next = (current + 1) % images.length;
      controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    slideTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xffd8e5df)),
    ),
    child: Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            width: double.infinity,
            height: constraints.maxWidth >= 700 ? 280 : 190,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: controller,
                  reverse: true,
                  itemCount: images.length,
                  onPageChanged: (index) => setState(() => current = index),
                  itemBuilder: (context, index) => Image.asset(
                    images[index],
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Color(0xffdcebe5),
                      child: Center(
                        child: Icon(
                          Icons.agriculture,
                          size: 72,
                          color: Color(0xff0d7c66),
                        ),
                      ),
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Color(0x66000000)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  bottom: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      images.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: current == index ? 24 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: current == index
                              ? const Color(0xffd6f36b)
                              : Colors.white70,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> formDialog(
  BuildContext context,
  String title,
  String table,
  List<String> labels,
  Map<String, Object?> Function(List<String>) make,
  VoidCallback saved, {
  int? recordId,
  List<String>? initialValues,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => RecordDialog(
      title: title,
      table: table,
      labels: labels,
      make: make,
      recordId: recordId,
      initialValues: initialValues,
    ),
  );
  if (result == true && context.mounted) saved();
}

Future<void> deleteRecord(
  BuildContext context,
  String table,
  int id,
  VoidCallback deleted,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const AppText('Delete record?'),
      content: const AppText('This record will be permanently deleted.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const AppText('Cancel'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const AppText('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await Store.instance.remove(table, id);
  deleted();
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: const AppText('Record deleted.')));
  }
}

class RecordDialog extends StatefulWidget {
  final String title, table;
  final List<String> labels;
  final Map<String, Object?> Function(List<String>) make;
  final int? recordId;
  final List<String>? initialValues;
  const RecordDialog({
    super.key,
    required this.title,
    required this.table,
    required this.labels,
    required this.make,
    this.recordId,
    this.initialValues,
  });
  @override
  State<RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<RecordDialog> {
  final form = GlobalKey<FormState>();
  late final List<TextEditingController> controllers;
  bool saving = false;
  String? error;
  bool numeric(String label) => RegExp(
    r'weight|price|quantity|rate|amount|payment|cost|wastage|transport|commission',
    caseSensitive: false,
  ).hasMatch(label);

  @override
  void initState() {
    super.initState();
    controllers = List.generate(
      widget.labels.length,
      (i) => TextEditingController(
        text: i < (widget.initialValues?.length ?? 0)
            ? widget.initialValues![i]
            : '',
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final values = widget.make(
        controllers.map((c) => c.text.trim()).toList(),
      );
      if (widget.recordId == null) {
        await Store.instance.add(widget.table, values);
      } else {
        await Store.instance.update(widget.table, widget.recordId!, values);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error =
              'Could not save. Check the values and use a unique animal tag.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppText(
                widget.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xff143b34),
                ),
              ),
              const SizedBox(height: 8),
              const AppText(
                'Enter the record details below.',
                style: TextStyle(color: Color(0xff63746c)),
              ),
              const SizedBox(height: 24),
              ...List.generate(
                widget.labels.length,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                    controller: controllers[i],
                    keyboardType: numeric(widget.labels[i])
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                    textInputAction: i == controllers.length - 1
                        ? TextInputAction.done
                        : TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: translate(context, widget.labels[i]),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return Localizations.localeOf(context).languageCode ==
                                'ur'
                            ? '${translate(context, widget.labels[i])} درج کریں۔'
                            : 'Please enter ${widget.labels[i].toLowerCase()}.';
                      }
                      if (numeric(widget.labels[i])) {
                        final n = double.tryParse(value.trim());
                        if (n == null || !n.isFinite || n < 0) {
                          return translate(
                            context,
                            'Enter a valid positive number.',
                          );
                        }
                      }
                      return null;
                    },
                  ),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AppText(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: saving ? null : save,
                child: AppText(
                  saving
                      ? 'Saving…'
                      : widget.recordId == null
                      ? 'Save record'
                      : 'Update record',
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: saving ? null : () => Navigator.of(context).pop(),
                child: const AppText('Cancel'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class Animals extends StatelessWidget {
  final VoidCallback changed;
  const Animals({super.key, required this.changed});

  static const fields = [
    'Tag / ID',
    'Breed',
    'Purchase date',
    'Purchase weight kg',
    'Purchase price Rs',
    'Current weight kg',
    'Market / seller',
    'Status',
  ];

  Map<String, Object?> values(List<String> v) => {
    'tag': v[0],
    'breed': v[1],
    'purchase_date': v[2],
    'purchase_weight': double.tryParse(v[3]) ?? 0,
    'purchase_price': double.tryParse(v[4]) ?? 0,
    'current_weight': double.tryParse(v[5]) ?? 0,
    'seller': v[6],
    'status': v[7],
  };

  List<String> initial(Map<String, Object?> r) => [
    '${r['tag'] ?? ''}',
    '${r['breed'] ?? ''}',
    '${r['purchase_date'] ?? day()}',
    '${r['purchase_weight'] ?? ''}',
    '${r['purchase_price'] ?? ''}',
    '${r['current_weight'] ?? ''}',
    '${r['seller'] ?? ''}',
    '${r['status'] ?? 'Farm par'}',
  ];

  @override
  Widget build(BuildContext c) => Frame(
    title: 'Animal management',
    subtitle: 'Purchase, breed, weight, seller and status for every animal.',
    action: FilledButton.icon(
      onPressed: () => formDialog(
        c,
        'Add new animal',
        'animals',
        fields,
        values,
        changed,
        initialValues: ['', '', day(), '', '', '', '', 'Farm par'],
      ),
      icon: const Icon(Icons.add),
      label: const AppText('Add animal'),
    ),
    child: FutureBuilder<List<Map<String, Object?>>>(
      future: Store.instance.all('animals'),
      builder: (c, s) {
        final records = s.data ?? [];
        return SimpleTable(
          headers: const [
            'Tag / breed',
            'Purchase',
            'Weight progress',
            'Seller',
            'Status',
          ],
          rows: records
              .map(
                (r) => [
                  '${r['tag']}\n${r['breed']}',
                  cash((r['purchase_price'] as num?) ?? 0),
                  '${r['purchase_weight']} → ${r['current_weight']} kg',
                  '${r['seller']}',
                  '${r['status']}',
                ],
              )
              .toList(),
          onEdit: (index) {
            final record = records[index];
            formDialog(
              c,
              'Edit animal',
              'animals',
              fields,
              values,
              changed,
              recordId: record['id'] as int,
              initialValues: initial(record),
            );
          },
          onDelete: (index) =>
              deleteRecord(c, 'animals', records[index]['id'] as int, changed),
        );
      },
    ),
  );
}

class SimpleTable extends StatelessWidget {
  final List<String> headers;
  final List<List<String>> rows;
  final void Function(int index)? onEdit;
  final void Function(int index)? onDelete;
  const SimpleTable({
    super.key,
    required this.headers,
    required this.rows,
    this.onEdit,
    this.onDelete,
  });
  bool get hasActions => onEdit != null || onDelete != null;

  Widget actions(BuildContext context, int index) => Wrap(
    spacing: 4,
    children: [
      if (onEdit != null)
        IconButton(
          tooltip: translate(context, 'Edit'),
          onPressed: () => onEdit!(index),
          icon: const Icon(Icons.edit_outlined),
        ),
      if (onDelete != null)
        IconButton(
          tooltip: translate(context, 'Delete'),
          onPressed: () => onDelete!(index),
          color: Theme.of(context).colorScheme.error,
          icon: const Icon(Icons.delete_outline),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 40,
              color: Color(0xff0d7c66),
            ),
            SizedBox(height: 12),
            AppText(
              'No records yet',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            SizedBox(height: 6),
            AppText(
              'New records will appear here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Column(
            children: List.generate(rows.length, (rowIndex) {
              final row = rows[rowIndex];
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xffe0e8e2)),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      row.first,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: Color(0xff143b34),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(),
                    ),
                    ...List.generate(headers.length - 1, (index) {
                      final i = index + 1;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText(
                              headers[i],
                              style: const TextStyle(
                                color: Color(0xff63746c),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            AppText(
                              row[i],
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (hasActions) ...[
                      const Divider(),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: actions(context, rowIndex),
                      ),
                    ],
                  ],
                ),
              );
            }),
          );
        }
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xffe0e8e2)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(
                  Color(0xffeaf1ec),
                ),
                dataRowMinHeight: 68,
                dataRowMaxHeight: double.infinity,
                columnSpacing: 24,
                columns: [
                  ...headers.map(
                    (h) => DataColumn(
                      label: AppText(
                        h,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  if (hasActions)
                    const DataColumn(
                      label: AppText(
                        'Actions',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
                rows: List.generate(rows.length, (rowIndex) {
                  final row = rows[rowIndex];
                  return DataRow(
                    cells: [
                      ...row.map(
                        (x) => DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: AppText(x),
                            ),
                          ),
                        ),
                      ),
                      if (hasActions) DataCell(actions(context, rowIndex)),
                    ],
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }
}

class Feed extends StatelessWidget {
  final VoidCallback changed;
  const Feed({super.key, required this.changed});
  static const purchaseFields = [
    'Feed type',
    'Quantity kg',
    'Rate / kg',
    'Supplier',
    'Purchase date',
    'Supplier payment',
  ];
  static const consumptionFields = [
    'Feed type',
    'Quantity kg',
    'Wastage kg',
    'Date',
    'Animal / group',
  ];

  Map<String, Object?> purchaseValues(List<String> v) => {
    'type': v[0],
    'quantity': double.tryParse(v[1]) ?? 0,
    'rate': double.tryParse(v[2]) ?? 0,
    'supplier': v[3],
    'date': v[4],
    'paid': double.tryParse(v[5]) ?? 0,
  };

  List<String> purchaseInitial(Map<String, Object?> r) => [
    '${r['type'] ?? ''}',
    '${r['quantity'] ?? ''}',
    '${r['rate'] ?? ''}',
    '${r['supplier'] ?? ''}',
    '${r['date'] ?? day()}',
    '${r['paid'] ?? 0}',
  ];

  Map<String, Object?> consumptionValues(List<String> v) => {
    'type': v[0],
    'quantity': double.tryParse(v[1]) ?? 0,
    'wastage': double.tryParse(v[2]) ?? 0,
    'date': v[3],
    'animal_tag': v[4],
  };

  List<String> consumptionInitial(Map<String, Object?> r) => [
    '${r['type'] ?? ''}',
    '${r['quantity'] ?? ''}',
    '${r['wastage'] ?? 0}',
    '${r['date'] ?? day()}',
    '${r['animal_tag'] ?? ''}',
  ];

  @override
  Widget build(BuildContext c) => Frame(
    title: 'Feed & stock management',
    subtitle: 'Silage, wanda, chokar, suppliers, rates and stock purchases.',
    action: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => formDialog(
            c,
            'Record feed purchase',
            'feed_purchases',
            purchaseFields,
            purchaseValues,
            changed,
            initialValues: ['', '', '', '', day(), '0'],
          ),
          icon: const Icon(Icons.add),
          label: const AppText('Record purchase'),
        ),
        FilledButton.tonalIcon(
          onPressed: () => formDialog(
            c,
            'Record feed usage',
            'feed_consumption',
            consumptionFields,
            consumptionValues,
            changed,
            initialValues: ['', '', '0', day(), ''],
          ),
          icon: const Icon(Icons.restaurant_outlined),
          label: const AppText('Record usage'),
        ),
      ],
    ),
    child: FutureBuilder<List<List<Map<String, Object?>>>>(
      future: Future.wait([
        Store.instance.all('feed_purchases'),
        Store.instance.all('feed_consumption'),
      ]),
      builder: (c, s) {
        final purchases = s.data?[0] ?? [];
        final usage = s.data?[1] ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppText(
              'Feed purchases',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SimpleTable(
              headers: const [
                'Feed',
                'Purchase qty',
                'Rate / kg',
                'Supplier',
                'Payment',
              ],
              rows: purchases
                  .map(
                    (r) => [
                      '${r['type']}',
                      '${r['quantity']} kg',
                      cash((r['rate'] as num?) ?? 0),
                      '${r['supplier']}',
                      cash((r['paid'] as num?) ?? 0),
                    ],
                  )
                  .toList(),
              onEdit: (index) {
                final record = purchases[index];
                formDialog(
                  c,
                  'Edit feed purchase',
                  'feed_purchases',
                  purchaseFields,
                  purchaseValues,
                  changed,
                  recordId: record['id'] as int,
                  initialValues: purchaseInitial(record),
                );
              },
              onDelete: (index) => deleteRecord(
                c,
                'feed_purchases',
                purchases[index]['id'] as int,
                changed,
              ),
            ),
            const SizedBox(height: 24),
            const AppText(
              'Feed usage',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SimpleTable(
              headers: const [
                'Feed',
                'Consumed',
                'Wastage',
                'Date',
                'Animal / group',
              ],
              rows: usage
                  .map(
                    (r) => [
                      '${r['type']}',
                      '${r['quantity']} kg',
                      '${r['wastage']} kg',
                      '${r['date']}',
                      '${r['animal_tag']}',
                    ],
                  )
                  .toList(),
              onEdit: (index) {
                final record = usage[index];
                formDialog(
                  c,
                  'Edit feed usage',
                  'feed_consumption',
                  consumptionFields,
                  consumptionValues,
                  changed,
                  recordId: record['id'] as int,
                  initialValues: consumptionInitial(record),
                );
              },
              onDelete: (index) => deleteRecord(
                c,
                'feed_consumption',
                usage[index]['id'] as int,
                changed,
              ),
            ),
          ],
        );
      },
    ),
  );
}

class Growth extends StatelessWidget {
  final VoidCallback changed;
  const Growth({super.key, required this.changed});

  Future<List<Map<String, Object?>>> load() => Store.instance.db.rawQuery(
    'SELECT w.*, a.purchase_weight FROM weights w '
    'LEFT JOIN animals a ON a.tag = w.animal_id '
    'ORDER BY w.date DESC, w.id DESC',
  );

  static const fields = ['Animal ID', 'Current weight kg', 'Date'];

  Map<String, Object?> values(List<String> v) => {
    'animal_id': v[0],
    'weight': double.tryParse(v[1]) ?? 0,
    'date': v[2],
  };

  List<String> initial(Map<String, Object?> r) => [
    '${r['animal_id'] ?? ''}',
    '${r['weight'] ?? ''}',
    '${r['date'] ?? day()}',
  ];

  @override
  Widget build(BuildContext c) => Frame(
    title: 'Weight & growth records',
    subtitle: 'Starting weight, current weight, gains and growth progress.',
    action: FilledButton.icon(
      onPressed: () => formDialog(
        c,
        'Add weight record',
        'weights',
        fields,
        values,
        changed,
        initialValues: ['', '', day()],
      ),
      icon: const Icon(Icons.add),
      label: const AppText('Add weight'),
    ),
    child: FutureBuilder<List<Map<String, Object?>>>(
      future: load(),
      builder: (c, s) {
        final records = s.data ?? [];
        return SimpleTable(
          headers: const [
            'Animal',
            'Starting weight',
            'Current weight',
            'Gain',
            'Date',
          ],
          rows: records.map((r) {
            final start = (r['purchase_weight'] as num?) ?? 0;
            final current = (r['weight'] as num?) ?? 0;
            return [
              '${r['animal_id']}',
              '$start kg',
              '$current kg',
              '${current - start} kg',
              '${r['date']}',
            ];
          }).toList(),
          onEdit: (index) {
            final record = records[index];
            formDialog(
              c,
              'Edit weight record',
              'weights',
              fields,
              values,
              changed,
              recordId: record['id'] as int,
              initialValues: initial(record),
            );
          },
          onDelete: (index) =>
              deleteRecord(c, 'weights', records[index]['id'] as int, changed),
        );
      },
    ),
  );
}

class Sales extends StatelessWidget {
  final VoidCallback changed;
  const Sales({super.key, required this.changed});
  static const fields = [
    'Factory name',
    'Animal ID',
    'Sale date',
    'Sale weight kg',
    'Rate / kg',
    'Transport cost',
    'Commission',
    'Payment received',
  ];

  Map<String, Object?> values(List<String> v) => {
    'factory': v[0],
    'animal_id': v[1],
    'date': v[2],
    'weight': double.tryParse(v[3]) ?? 0,
    'rate': double.tryParse(v[4]) ?? 0,
    'total': (double.tryParse(v[3]) ?? 0) * (double.tryParse(v[4]) ?? 0),
    'transport': double.tryParse(v[5]) ?? 0,
    'commission': double.tryParse(v[6]) ?? 0,
    'received': double.tryParse(v[7]) ?? 0,
  };

  List<String> initial(Map<String, Object?> r) => [
    '${r['factory'] ?? ''}',
    '${r['animal_id'] ?? ''}',
    '${r['date'] ?? day()}',
    '${r['weight'] ?? ''}',
    '${r['rate'] ?? ''}',
    '${r['transport'] ?? 0}',
    '${r['commission'] ?? 0}',
    '${r['received'] ?? 0}',
  ];

  @override
  Widget build(BuildContext c) => Frame(
    title: 'Factory sales',
    subtitle: 'Factory name, sale weight, rate, deductions and payment.',
    action: FilledButton.icon(
      onPressed: () => formDialog(
        c,
        'Log factory sale',
        'sales',
        fields,
        values,
        changed,
        initialValues: ['', '', day(), '', '', '0', '0', '0'],
      ),
      icon: const Icon(Icons.add),
      label: const AppText('Log factory sale'),
    ),
    child: FutureBuilder<List<Map<String, Object?>>>(
      future: Store.instance.all('sales'),
      builder: (c, s) {
        final records = s.data ?? [];
        return SimpleTable(
          headers: const [
            'Factory',
            'Date',
            'Animal',
            'Sale weight',
            'Gross sale',
            'Received',
          ],
          rows: records
              .map(
                (r) => [
                  '${r['factory']}',
                  '${r['date']}',
                  '${r['animal_id']}',
                  '${r['weight']} kg',
                  cash((r['total'] as num?) ?? 0),
                  cash((r['received'] as num?) ?? 0),
                ],
              )
              .toList(),
          onEdit: (index) {
            final record = records[index];
            formDialog(
              c,
              'Edit factory sale',
              'sales',
              fields,
              values,
              changed,
              recordId: record['id'] as int,
              initialValues: initial(record),
            );
          },
          onDelete: (index) =>
              deleteRecord(c, 'sales', records[index]['id'] as int, changed),
        );
      },
    ),
  );
}

class Expenses extends StatelessWidget {
  final VoidCallback changed;
  const Expenses({super.key, required this.changed});
  static const fields = [
    'Category',
    'Description',
    'Amount Rs',
    'Date',
    'Type',
  ];

  Map<String, Object?> values(List<String> v) => {
    'category': v[0],
    'description': v[1],
    'amount': double.tryParse(v[2]) ?? 0,
    'date': v[3],
    'kind': v[4],
  };

  List<String> initial(Map<String, Object?> r) => [
    '${r['category'] ?? ''}',
    '${r['description'] ?? ''}',
    '${r['amount'] ?? ''}',
    '${r['date'] ?? day()}',
    '${r['kind'] ?? 'paid'}',
  ];

  @override
  Widget build(BuildContext c) => Frame(
    title: 'Expenses & accounts',
    subtitle:
        'Cash paid/received, labour, doctor, transport and other expenses.',
    action: FilledButton.icon(
      onPressed: () => formDialog(
        c,
        'Add expense',
        'expenses',
        fields,
        values,
        changed,
        initialValues: ['', '', '', day(), 'paid'],
      ),
      icon: const Icon(Icons.add),
      label: const AppText('Add expense'),
    ),
    child: FutureBuilder<List<Map<String, Object?>>>(
      future: Store.instance.all('expenses'),
      builder: (c, s) {
        final records = s.data ?? [];
        return SimpleTable(
          headers: const ['Category', 'Description', 'Date', 'Amount', 'Type'],
          rows: records
              .map(
                (r) => [
                  '${r['category']}',
                  '${r['description']}',
                  '${r['date']}',
                  cash((r['amount'] as num?) ?? 0),
                  '${r['kind']}',
                ],
              )
              .toList(),
          onEdit: (index) {
            final record = records[index];
            formDialog(
              c,
              'Edit expense',
              'expenses',
              fields,
              values,
              changed,
              recordId: record['id'] as int,
              initialValues: initial(record),
            );
          },
          onDelete: (index) =>
              deleteRecord(c, 'expenses', records[index]['id'] as int, changed),
        );
      },
    ),
  );
}

class Health extends StatelessWidget {
  final VoidCallback changed;
  const Health({super.key, required this.changed});
  static const fields = [
    'Animal ID',
    'Treatment / medicine',
    'Notes',
    'Cost Rs',
    'Doctor',
    'Date',
  ];

  Map<String, Object?> values(List<String> v) => {
    'animal_id': v[0],
    'type': v[1],
    'notes': v[2],
    'cost': double.tryParse(v[3]) ?? 0,
    'doctor': v[4],
    'date': v[5],
  };

  List<String> initial(Map<String, Object?> r) => [
    '${r['animal_id'] ?? ''}',
    '${r['type'] ?? ''}',
    '${r['notes'] ?? ''}',
    '${r['cost'] ?? ''}',
    '${r['doctor'] ?? ''}',
    '${r['date'] ?? day()}',
  ];

  @override
  Widget build(BuildContext context) => Frame(
    title: 'Health & treatment',
    subtitle: 'Keep a dated record of treatments, medicine and doctor fees.',
    action: FilledButton.icon(
      icon: const Icon(Icons.add),
      label: const AppText('Add treatment'),
      onPressed: () => formDialog(
        context,
        'Add treatment',
        'health',
        fields,
        values,
        changed,
        initialValues: ['', '', '', '', '', day()],
      ),
    ),
    child: FutureBuilder<List<Map<String, Object?>>>(
      future: Store.instance.all('health'),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const AppText('Unable to load treatment records.');
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final records = snapshot.data!;
        return SimpleTable(
          headers: const [
            'Animal',
            'Treatment',
            'Notes',
            'Cost',
            'Doctor',
            'Date',
          ],
          rows: records
              .map(
                (r) => [
                  '${r['animal_id']}',
                  '${r['type']}',
                  '${r['notes']}',
                  cash((r['cost'] as num?) ?? 0),
                  '${r['doctor']}',
                  '${r['date']}',
                ],
              )
              .toList(),
          onEdit: (index) {
            final record = records[index];
            formDialog(
              context,
              'Edit treatment',
              'health',
              fields,
              values,
              changed,
              recordId: record['id'] as int,
              initialValues: initial(record),
            );
          },
          onDelete: (index) => deleteRecord(
            context,
            'health',
            records[index]['id'] as int,
            changed,
          ),
        );
      },
    ),
  );
}

class Reports extends StatelessWidget {
  const Reports({super.key});
  Future<List<List<Map<String, Object?>>>> _load() => Future.wait([
    Store.instance.db.rawQuery(
      'SELECT factory, SUM(total) AS sales, SUM(received) AS received FROM sales GROUP BY factory',
    ),
    Store.instance.db.rawQuery(
      "SELECT substr(date,1,7) AS month, type, SUM(quantity) AS quantity, SUM(wastage) AS wastage FROM feed_consumption GROUP BY substr(date,1,7),type ORDER BY month DESC",
    ),
    Store.instance.db.rawQuery(
      "SELECT tag, breed, current_weight, purchase_price FROM animals WHERE status IN ('Farm par','Sick')",
    ),
  ]);
  @override
  Widget build(BuildContext context) => Frame(
    title: 'Reports & insights',
    subtitle: 'Recorded factory sales, feed usage and your active herd.',
    child: FutureBuilder<List<List<Map<String, Object?>>>>(
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const AppText(
            'Unable to load reports. Please reopen this screen.',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final groups = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppText(
              'Factory sales',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SimpleTable(
              headers: const ['Factory', 'Sales', 'Received', 'Outstanding'],
              rows: groups[0].map((r) {
                final sales = (r['sales'] as num?) ?? 0,
                    received = (r['received'] as num?) ?? 0;
                return [
                  '${r['factory']}',
                  cash(sales),
                  cash(received),
                  cash(sales - received),
                ];
              }).toList(),
            ),
            const SizedBox(height: 24),
            const AppText(
              'Monthly feed usage',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SimpleTable(
              headers: const ['Month', 'Feed', 'Consumed', 'Wastage'],
              rows: groups[1]
                  .map(
                    (r) => [
                      '${r['month']}',
                      '${r['type']}',
                      '${r['quantity']} kg',
                      '${r['wastage']} kg',
                    ],
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            const AppText(
              'Unsold herd',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SimpleTable(
              headers: const [
                'Animal',
                'Breed',
                'Current weight',
                'Purchase cost',
              ],
              rows: groups[2]
                  .map(
                    (r) => [
                      '${r['tag']}',
                      '${r['breed']}',
                      '${r['current_weight']} kg',
                      cash((r['purchase_price'] as num?) ?? 0),
                    ],
                  )
                  .toList(),
            ),
          ],
        );
      },
    ),
  );
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => Frame(
    title: 'Profile',
    subtitle: 'Farm owner and contact information.',
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 480 ? 20 : 32,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xffe0e8e2)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0d000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final photo = ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/naveed_pic.jpg',
                  width: constraints.maxWidth >= 620 ? 220 : 190,
                  height: constraints.maxWidth >= 620 ? 270 : 220,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, _, _) => Container(
                    width: 190,
                    height: 220,
                    color: const Color(0xffeaf1ec),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.person,
                      size: 88,
                      color: Color(0xff0d7c66),
                    ),
                  ),
                ),
              );
              const details = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppText(
                    'Rana Naveed',
                    style: TextStyle(
                      color: Color(0xff143b34),
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  AppText(
                    'Farm owner',
                    style: TextStyle(
                      color: Color(0xff0d7c66),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 24),
                  ProfileDetail(
                    icon: Icons.phone_outlined,
                    label: 'Phone number',
                    value: '03074600729',
                  ),
                  SizedBox(height: 14),
                  ProfileDetail(
                    icon: Icons.phone_outlined,
                    label: 'Alternate phone number',
                    value: '03437600729',
                  ),
                  SizedBox(height: 14),
                  ProfileDetail(
                    icon: Icons.location_on_outlined,
                    label: 'Address',
                    value: 'Karma wala Chowk, Pakpattan',
                  ),
                ],
              );
              if (constraints.maxWidth >= 620) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    photo,
                    const SizedBox(width: 32),
                    const Expanded(child: details),
                  ],
                );
              }
              return Column(
                children: [
                  photo,
                  const SizedBox(height: 24),
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: details,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class ProfileDetail extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const ProfileDetail({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xffeaf5f1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xff0d7c66), size: 21),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              label,
              style: const TextStyle(color: Color(0xff63746c), fontSize: 12),
            ),
            const SizedBox(height: 3),
            SelectableText(
              value,
              style: const TextStyle(
                color: Color(0xff143b34),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
