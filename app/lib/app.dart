import 'package:fluent_ui/fluent_ui.dart';

import 'screens/profile_list_screen.dart';
import 'screens/settings_screen.dart';

class UnisonApp extends StatelessWidget {
  const UnisonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'Unison',
      themeMode: ThemeMode.system,
      darkTheme: FluentThemeData.dark(),
      theme: FluentThemeData.light(),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      pane: NavigationPane(
        selected: _selectedIndex,
        onChanged: (i) => setState(() => _selectedIndex = i),
        displayMode: PaneDisplayMode.compact,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.sync),
            title: const Text('Profiles'),
            body: const ProfileListScreen(),
          ),
        ],
        footerItems: [
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text('Settings'),
            body: const SettingsScreen(),
          ),
        ],
      ),
    );
  }
}
