import 'package:snowfluff/pages/main_page.dart';
import 'package:snowfluff/pages/provider.dart';
import 'package:snowfluff/router/app_pages.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_router.dart';

part 'router.g.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');
String startupInitialLocation = AppRouter.home;
@riverpod
GoRouter router(Ref ref) {
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: false,
    initialLocation: startupInitialLocation,
    routes: [
      ShellRoute(
        routes: AppPages.shellRouter,
        navigatorKey: shellNavigatorKey,
        builder: (BuildContext context, GoRouterState state, Widget child) =>
            MainPage(child: child),
      ),
      ...AppPages.rootRouter
    ],
  );
  String lastPath = '';
  router.routerDelegate.addListener(() {
    final currentState = router.state;
    final currentPath = currentState.path ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(routeHistoryProvider.notifier).observeRoute(currentState);
      if (currentPath == lastPath) return; // 路径未变时跳过面板/底栏更新
      lastPath = currentPath;
      ref.read(currentRouterPathProvider.notifier).updatePanelDetail(currentPath);
    });
  });
  ref.onDispose(router.dispose);
  return router;
}

class SnowfluffObserver extends NavigatorObserver {
  final Ref ref;

  SnowfluffObserver({required this.ref});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _showOrHideFooter(route.settings.name ?? '');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _showOrHideFooter(previousRoute?.settings.name ?? '');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _showOrHideFooter(newRoute?.settings.name ?? '');
  }

  void _showOrHideFooter(String name) {
    if (name.isEmpty) return;
    ref.read(currentRouterPathProvider.notifier).updatePanelDetail(name);
  }
}
