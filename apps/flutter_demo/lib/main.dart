import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'screens/home_screen.dart';
import 'screens/sync_screen.dart';
import 'screens/settings_screen.dart';
import 'services/demo_service.dart';

void main() {
  runApp(const MerkleKVDemoApp());
}

class MerkleKVDemoApp extends StatelessWidget {
  const MerkleKVDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => DemoService(),
        ),
      ],
      child: MaterialApp.router(
        title: 'MerkleKV Mobile Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        routerConfig: _router,
      ),
    );
  }

  static final GoRouter _router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        name: 'home',
        builder: (BuildContext context, GoRouterState state) {
          return const HomeScreen();
        },
        routes: <RouteBase>[
          GoRoute(
            path: '/sync',
            name: 'sync',
            builder: (BuildContext context, GoRouterState state) {
              return const SyncScreen();
            },
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (BuildContext context, GoRouterState state) {
              return const SettingsScreen();
            },
          ),
        ],
      ),
    ],
  );
}
