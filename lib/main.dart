import 'package:flutter/material.dart';
import 'screens/portfolio_screen.dart';
import 'screens/signals_screen.dart';
import 'screens/watchlist_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(const PsxSwingApp());
}

class PsxSwingApp extends StatelessWidget {
  const PsxSwingApp({super.key});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0E9F6E);
    return MaterialApp(
      title: 'PSX Swing Trader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          brightness: Brightness.dark,
          primary: green,
        ),
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        cardColor: const Color(0xFF161B22),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1117),
          elevation: 0,
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _screens = const [PortfolioScreen(), SignalsScreen(), WatchlistScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: const Color(0xFF161B22),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Portfolio'),
          NavigationDestination(icon: Icon(Icons.bolt_outlined), label: 'Signals'),
          NavigationDestination(icon: Icon(Icons.visibility_outlined), label: 'Watchlist'),
        ],
      ),
    );
  }
}
