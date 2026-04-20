import 'package:snowfluff/common/music_handler.dart';
import 'package:snowfluff/common/playback_state_cache_service.dart';
import 'package:snowfluff/common/settings_service.dart';
import 'package:snowfluff/router/app_router.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:cached_network_image/cached_network_image.dart';

part 'provider.g.dart';

@riverpod
class ThemeModeNotifier extends _$ThemeModeNotifier {
  @override
  ThemeMode build() => SettingsService.themeMode;
  void setTheme(ThemeMode mode) {
    if (state == mode) return;
    state = mode;
    SettingsService.setThemeMode(mode);
  }

  void toggleTheme() {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setTheme(next);
  }
}

@riverpod
class DyColorNotifier extends _$DyColorNotifier {
  @override
  Color build() {
    final int? cachedArgb =
        SnowfluffMusicHandler().cachedBackgroundColorArgb ??
        PlaybackStateCacheService.bootstrapBackgroundColorArgb;
    if (cachedArgb != null) {
      return Color(cachedArgb);
    }
    return const Color(0xFF101010);
  }

  void setColor(Color color) {
    state = color;
  }
}

@riverpod
class CurrentRouterPath extends _$CurrentRouterPath {
  @override
  String build() => '/';
  void updatePanelDetail(String newValue) {
    if (state != newValue) {
      state = newValue;
    }
  }
}

@riverpod
Stream<MediaItem?> mediaItem(Ref ref) {
  return SnowfluffMusicHandler().mediaItem.stream;
}

@riverpod
Stream<List<MediaItem>> mediaList(Ref ref) {
  return SnowfluffMusicHandler().queue.stream;
}

@riverpod
Future<ColorScheme> dynamicColor(Ref ref) async {
  final artUrl = ref.watch(
    mediaItemProvider.select((value) => value.value?.artUri?.toString() ?? ''),
  );
  // proxyImageUrl格式固定: ?url=<ENCODED>[&pid=...]
  // 在url=值末尾（首个&之前）直接插入%3Fparam%3D100y100（即?param=100y100的编码形式）
  final int amp = artUrl.indexOf('&');
  final String colorImageUrl = artUrl.isEmpty
      ? artUrl
      : (amp >= 0
          ? '${artUrl.substring(0, amp)}%3Fparam%3D100y100${artUrl.substring(amp)}'
          : '$artUrl%3Fparam%3D100y100');
  var colorScheme = await ColorScheme.fromImageProvider(
    provider: CachedNetworkImageProvider(
      colorImageUrl,
      headers: {
        // 防止403
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/42.0.2311.135 Safari/537.36 Edge/13.10586',
        'Referer': 'https://music.163.com/',
      },
    ),
  );
  return colorScheme;
}

@riverpod
Stream<PlaybackState?> playbackState(Ref ref) {
  return SnowfluffMusicHandler().playbackState.stream;
}

@riverpod
Stream<bool> isFMMode(Ref ref) {
  return SnowfluffMusicHandler().queueTitle.stream.map(
    (title) => title == SnowfluffMusicHandler.kFMQueueTitle,
  );
}

@riverpod
AudioServiceRepeatMode loopMode(Ref ref) {
  // 监听播放状态中的循环模式
  return ref.watch(
    playbackStateProvider.select(
      (s) => s.value?.repeatMode ?? AudioServiceRepeatMode.none,
    ),
  );
}

// 页面历史，用于导航栏前进/后退
class RouteHistoryState {
  final List<String> back;
  final String? current;
  final List<String> forward;
  const RouteHistoryState({
    this.back = const [],
    this.current,
    this.forward = const [],
  });
  bool get canBack => back.isNotEmpty;
  bool get canForward => forward.isNotEmpty;
  RouteHistoryState copyWith({
    List<String>? back,
    String? current,
    List<String>? forward,
  }) {
    return RouteHistoryState(
      back: back ?? this.back,
      current: current ?? this.current,
      forward: forward ?? this.forward,
    );
  }
}

class RouteHistoryNotifier extends Notifier<RouteHistoryState> {
  static const int _maxHistory = 200;
  bool _historyNavigationInProgress = false;

  @override
  RouteHistoryState build() => const RouteHistoryState();

  bool _shouldTrackPath(String path) {
    return path == AppRouter.home ||
        path == AppRouter.discover ||
        path == AppRouter.playlist ||
        path == AppRouter.library ||
        path == AppRouter.settings ||
        path == AppRouter.playqueue ||
        path == AppRouter.album ||
        path == AppRouter.artist ||
        path == AppRouter.search;
  }

  String _normalizeLocation(GoRouterState state) {
    final path = state.path ?? '';
    if (path == AppRouter.playlist) {
      final idFromExtra = state.extra is int ? state.extra as int : null;
      final idFromQuery = int.tryParse(state.uri.queryParameters['id'] ?? '');
      final id = idFromExtra ?? idFromQuery;
      if (id != null) {
        return '${AppRouter.playlist}?id=$id';
      }
    }
    if (path == AppRouter.search) {
      final q = (state.uri.queryParameters['q'] ?? '').trim();
      return q.isEmpty
          ? AppRouter.search
          : '${AppRouter.search}?q=${Uri.encodeQueryComponent(q)}';
    }
    if (path == AppRouter.artist) {
      final idFromQuery = int.tryParse(state.uri.queryParameters['id'] ?? '');
      final idFromExtra = state.extra is int ? state.extra as int : null;
      final id = idFromQuery ?? idFromExtra;
      return id == null ? AppRouter.artist : '${AppRouter.artist}?id=$id';
    }
    if (path == AppRouter.album) {
      final idFromQuery = int.tryParse(state.uri.queryParameters['id'] ?? '');
      final idFromExtra = state.extra is int ? state.extra as int : null;
      final id = idFromQuery ?? idFromExtra;
      return id == null ? AppRouter.album : '${AppRouter.album}?id=$id';
    }
    return state.uri.toString();
  }

  void observeRoute(GoRouterState routerState) {
    final path = routerState.path ?? '';
    if (!_shouldTrackPath(path)) return; // 排除 play/login

    final location = _normalizeLocation(routerState);
    final current = state.current;

    if (_historyNavigationInProgress) {
      state = state.copyWith(current: location);
      _historyNavigationInProgress = false;
      return;
    }

    if (current == null) {
      state = state.copyWith(current: location);
      return;
    }

    if (current == location) return;

    final newBack = [...state.back, current];
    if (newBack.length > _maxHistory) {
      newBack.removeAt(0);
    }

    state = state.copyWith(back: newBack, current: location, forward: const []);
  }

  String? goBackLocation() {
    if (!state.canBack || state.current == null) return null;

    final newBack = [...state.back];
    final target = newBack.removeLast();
    final newForward = [...state.forward, state.current!];

    _historyNavigationInProgress = true;
    state = state.copyWith(back: newBack, current: target, forward: newForward);
    return target;
  }

  String? goForwardLocation() {
    if (!state.canForward || state.current == null) return null;

    final newForward = [...state.forward];
    final target = newForward.removeLast();
    final newBack = [...state.back, state.current!];
    if (newBack.length > _maxHistory) {
      newBack.removeAt(0);
    }

    _historyNavigationInProgress = true;
    state = state.copyWith(back: newBack, current: target, forward: newForward);
    return target;
  }
}

final routeHistoryProvider =
    NotifierProvider<RouteHistoryNotifier, RouteHistoryState>(
      RouteHistoryNotifier.new,
    );

// 状态管理
final themeColorProvider = StateNotifierProvider<ThemeColorNotifier, Color>((
  ref,
) {
  return ThemeColorNotifier();
});

class ThemeColorNotifier extends StateNotifier<Color> {
  // 初始化时从 Hive 读取
  ThemeColorNotifier() : super(SettingsService.themeColor);

  Future<void> setColor(Color color) async {
    state = color;
    await SettingsService.setThemeColor(color);
  }
}
