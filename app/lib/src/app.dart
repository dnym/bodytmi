import 'dart:io' show Platform;

import 'package:material_ui/material_ui.dart';

import 'body.dart';
import 'food.dart';
import 'format.dart';
import 'health_connect.dart' show refreshStepsQuietly;
import 'reminders.dart' show refreshRemindersQuietly;
import 'more.dart';
import 'profile.dart';
import 'quick_entry.dart';
import 'theme.dart';
import 'today.dart';
import 'train.dart';

final class BodyTmiApp extends StatelessWidget {
  const BodyTmiApp({super.key, required this.profile, this.clock});

  final ProfileClient profile;

  /// Fixed time for tests and screenshots.
  final DateTime? clock;

  @override
  Widget build(BuildContext context) => ProfileScope(
    profile: profile,
    child: MaterialApp(
      title: 'BodyTMI',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: HomeShell(clock: clock),
    ),
  );
}

/// Design A: five fixed destinations in a bottom navigation bar.
final class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.clock});
  final DateTime? clock;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

final class _HomeShellState extends State<HomeShell> {
  int index = 0;
  bool _stepsRefreshed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Health Connect exists only on Android phones (not in tests).
    if (!_stepsRefreshed && Platform.isAndroid) {
      _stepsRefreshed = true;
      final profile = ProfileScope.of(context);
      refreshStepsQuietly(profile);
      refreshRemindersQuietly(profile);
    }
  }

  static const _titles = ['Today', 'Train', 'Food', 'Body', 'More'];

  @override
  Widget build(BuildContext context) {
    final now = widget.clock ?? DateTime.now();
    final screens = [
      TodayScreen(clock: widget.clock),
      const TrainScreen(),
      FoodScreen(clock: widget.clock),
      BodyScreen(clock: widget.clock),
      const MoreScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        actions: [
          if (index == 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton.filledTonal(
                tooltip: 'Quick add',
                onPressed: () => showQuickAdd(context, clock: widget.clock),
                icon: const Icon(Icons.add),
              ),
            ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_titles[index]),
            if (index == 0)
              Text(
                Fmt.of(context).longDate(now),
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.of(context).muted,
                ),
              ),
          ],
        ),
      ),
      body: IndexedStack(index: index, children: screens),
      floatingActionButton: index == 2
          ? FloatingActionButton.extended(
              onPressed: () => openFoodEntry(context, clock: widget.clock),
              icon: const Icon(Icons.add),
              label: const Text('Add food'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Train',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: 'Food',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Body',
          ),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
