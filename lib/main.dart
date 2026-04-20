import 'dart:async';
import 'dart:io';
import 'package:snowfluff/common/app_theme.dart';
import 'package:snowfluff/common/settings_service.dart';
import 'package:snowfluff/common/playback_state_cache_service.dart';
import 'package:snowfluff/pages/provider.dart';
import 'package:snowfluff/router/app_router.dart';
import 'package:snowfluff/router/router.dart';
import 'package:snowfluff/utils/device_config.dart';
import 'package:flutter/material.dart';
import 'package:snowfluff/common/local_proxy_service.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ncm_api/api/agent.dart';
import 'package:audio_service/audio_service.dart';
import 'package:snowfluff/common/music_handler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<String> _resolveInitialLocation() async {
  try {
    await AppStartup.apiReady;
    final uri = Uri.parse('https://music.163.com');
    final cookies = await SnowfluffMusicManager.cookieJar.loadForRequest(uri);
    return cookies.isEmpty ? AppRouter.login : AppRouter.home;
  } catch (_) {
    return AppRouter.login;
  }
}

/// 同步尝试跳转登录页(context已就绪)
bool _tryRedirectToLogin() {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return false;
  final router = GoRouter.of(context);
  if (router.state.path != AppRouter.login) {
    router.replace(AppRouter.login);
  }
  return true;
}

Future<void> _redirectToLoginWhenReady() async {
  // 在runApp之后的网络请求完成后才被调用，context已就绪
  if (_tryRedirectToLogin()) return;
  // try again
  final completer = Completer<void>();
  WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
  await completer.future;
  _tryRedirectToLogin();
}

Future<void> _checkLoginStatusInBackground() async {
  try {
    await AppStartup.apiReady;
    final uri = Uri.parse('https://music.163.com');
    final cookies = await SnowfluffMusicManager.cookieJar.loadForRequest(uri);
    if (cookies.isEmpty) return;
    final status = await SnowfluffMusicManager()
        .loginStatus()
        .timeout(const Duration(seconds: 3));
    // 接口返回code=200且account/profile为null视为登录已失效
    final isExpired =
        status?.code == 200 && status?.account == null && status?.profile == null;
    if (!isExpired) return;
    await _redirectToLoginWhenReady();
  } catch (_) {
    // 后台校验失败不阻塞应用启动
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final themeColor = ref.watch(themeColorProvider);
    return ScreenUtilInit(
      designSize: DeviceConfig().designSize,
      builder: (_, _) => Consumer(
        builder: (_, _, _) {
          return AnnotatedRegion(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemStatusBarContrastEnforced: false,
              systemNavigationBarContrastEnforced: false,
            ),
            child: MaterialApp.router(
              title: 'Snowfluff',
              themeMode: themeMode,
              darkTheme: AppTheme.dark(themeColor),
              theme: AppTheme.light(themeColor),
              routerConfig: router,
            ),
          );
        },
      ),
    );
  }
}

class AppStartup {
  AppStartup._();
  // 提前发起，供_initApi和main()共享，不重复调用
  static final Future<String> appDocDirPath =
      getApplicationDocumentsDirectory().then((d) => d.path);
  static final Future<void> apiReady = _initApi();
  static final Future<void> audioReady = _initAudio();
  static Future<void> _initApi() async {
    final path = await appDocDirPath;
    await SnowfluffMusicManager().init(
      cookiePath: '$path/_cookies',
      debug: false,
    );
  }

  static Future<void> _initAudio() async {
    await apiReady;
    await LocalProxyService().start();
    final SnowfluffMusicHandler handler = await AudioService.init(
      builder: () => SnowfluffMusicHandler(),
      config: AudioServiceConfig(
        androidNotificationChannelId:
            'com.github.eeentity.snowfluff.channel.audio',
        androidNotificationChannelName: 'Music Playback',
      ),
    );
    await handler.restoreFromCache();
  }

  static Future<void> warmPlatformFeatures() async {
    if (Platform.isLinux) {
      JustAudioMediaKit.ensureInitialized(); // Linux需要初始化
    }
    if (Platform.isAndroid) {
      await FlutterDisplayMode.setHighRefreshRate();
      JustAudioMediaKit.bufferSize = 8 * 1024 * 1024; // mpv缓冲区，默认32MB
      // Android默认用了原生音频后端
      PaintingBinding.instance.imageCache.maximumSizeBytes = 40 * 1024 * 1024; // 图片缓存
      PaintingBinding.instance.imageCache.maximumSize = 32;
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final Future<void> apiReadyFuture = AppStartup.apiReady;
  final Future<void> audioReadyFuture = AppStartup.audioReady;
  unawaited(AppStartup.warmPlatformFeatures().catchError((_) {}));
  final initialLocationFuture = _resolveInitialLocation();
  Hive.init('${await AppStartup.appDocDirPath}/hive');
  final Future<void> playbackPrimeFuture =
      PlaybackStateCacheService().primeBootstrapBackgroundColor();
  final Future<void> settingsInitFuture = SettingsService.init();
  final Future<bool> deviceConfigLoadedFuture = DeviceConfig().loadConfig();
  final List<dynamic> startupResults = await Future.wait<dynamic>(<Future<dynamic>>[
    playbackPrimeFuture,
    settingsInitFuture,
    deviceConfigLoadedFuture,
  ]);
  bool isDeviceConfigLoaded = startupResults[2] as bool;
  if (!isDeviceConfigLoaded) {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    if (view.physicalSize == Size.zero) {
      final completer = Completer<void>();
      void listener() {
        if (view.physicalSize != Size.zero) {
          WidgetsBinding.instance.platformDispatcher.onMetricsChanged = null;
          completer.complete();
        }
      }
      // 绑定监听
      WidgetsBinding.instance.platformDispatcher.onMetricsChanged = listener;
      // 等待尺寸准备就绪
      await completer.future;
    }
    await DeviceConfig().init(view.physicalSize, view.devicePixelRatio);
  }
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  switch (DeviceConfig.layoutMode) {
    case LayoutMode.mobile:
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]);
    case LayoutMode.tablet:
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    case LayoutMode.desktop:
      break;
  }
  final String resolvedInitialLocation = await initialLocationFuture;
  await Future.wait<void>(<Future<void>>[
    apiReadyFuture,
    audioReadyFuture,
  ]);
  startupInitialLocation = resolvedInitialLocation;
  unawaited(_checkLoginStatusInBackground());
  runApp(const ProviderScope(child: MyApp()));
}
