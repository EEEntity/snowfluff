import 'package:snowfluff/pages/album/album_page.dart';
import 'package:snowfluff/pages/artist/artist_page.dart';
import 'package:snowfluff/pages/discover/discover_page.dart';
import 'package:snowfluff/pages/library/library_page.dart';
import 'package:snowfluff/pages/login/login_page.dart';
import 'package:snowfluff/pages/play/play_page.dart';
import 'package:snowfluff/pages/playlist/playlist_page.dart';
import 'package:snowfluff/pages/playqueue/playqueue_page.dart';
import 'package:snowfluff/pages/search/search_page.dart';
import 'package:snowfluff/pages/settings/settings_page.dart';
import 'package:snowfluff/router/app_router.dart';
import 'package:snowfluff/router/router.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

class AppPages {
  // 底部播放条需要显示
  static final shellRouter = [
    GoRoute(
      path: AppRouter.home,
      pageBuilder: (context, state) => NoTransitionPage(child: LibraryPage()),
    ),
    GoRoute(
      path: AppRouter.discover,
      pageBuilder: (context, state) => NoTransitionPage(child: DiscoverPage()),
    ),
    GoRoute(
      path: AppRouter.playlist,
      pageBuilder: (context, state) {
        final idFromExtra = state.extra is int ? state.extra as int : null;
        final idFromQuery = int.tryParse(state.uri.queryParameters['id'] ?? '');
        final playlistId = idFromExtra ?? idFromQuery ?? 0;
        return NoTransitionPage(child: PlaylistPage(playlistId));
      },
    ),
    GoRoute(
      path: AppRouter.album,
      pageBuilder: (context, state) {
        final idFromExtra = state.extra is int ? state.extra as int : null;
        final idFromQuery = int.tryParse(state.uri.queryParameters['id'] ?? '');
        final albumId = idFromExtra ?? idFromQuery ?? 0;
        return NoTransitionPage(child: AlbumPage(albumId));
      },
    ),
    GoRoute(
      path: AppRouter.library,
      pageBuilder: (context, state) => NoTransitionPage(child: LibraryPage()),
    ),
    GoRoute(
      path: AppRouter.settings,
      pageBuilder: (context, state) => NoTransitionPage(child: SettingsPage()),
    ),
    GoRoute(
      path: AppRouter.playqueue,
      pageBuilder: (context, state) => NoTransitionPage(child: const PlayQueuePage()),
    ),
    GoRoute(
      path: AppRouter.search,
      pageBuilder: (context, state) {
        final keyword = (state.uri.queryParameters['q'] ?? '').trim();
        return NoTransitionPage(
          key: state.pageKey,
          child: SearchPage(keyword),
        );
      },
    ),
    GoRoute(
      path: AppRouter.artist,
      pageBuilder: (context, state) {
        final ifFromExtra = state.extra is int ? state.extra as int : null;
        final idFromQuery = int.tryParse(state.uri.queryParameters['id'] ?? '');
        final artistId = ifFromExtra ?? idFromQuery ?? 0;
        return NoTransitionPage(child: ArtistPage(artistId));
      }
    )
  ];
  // 全屏页面
  static final rootRouter = [
    GoRoute(
      path: AppRouter.play,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder:(context, state) => buildPageWithSlideUpTransition(state: state, child: PlayPage()),
    ),
    GoRoute(
      path: AppRouter.login,
      builder: (context, state) => const LoginPage(),
    )
  ];
  static Page<dynamic> buildPageWithSlideUpTransition({
    required GoRouterState state,
    required Widget child,
  }) {
    return CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 400),
      reverseTransitionDuration: const Duration(milliseconds: 400),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0); // 从底部开始
        const end = Offset.zero;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.ease,
          reverseCurve: Curves.ease,
        );
        final tween = Tween(begin: begin, end: end);
        return SlideTransition( // 向上滑，
          position: curved.drive(tween),
          child: child,
        );
      }
    );
  }
}
