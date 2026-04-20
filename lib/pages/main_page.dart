import 'dart:ui';
import 'dart:async';
import 'package:snowfluff/common/music_handler.dart';
import 'package:snowfluff/common/settings_service.dart';
import 'package:snowfluff/widgets/menu_bar.dart';
import 'package:snowfluff/pages/play/play_page.dart';
import 'package:snowfluff/pages/play/provider.dart';
import 'package:snowfluff/pages/provider.dart';
import 'package:snowfluff/router/app_router.dart';
import 'package:snowfluff/router/router.dart';
import 'package:snowfluff/utils/device_config.dart';
import 'package:snowfluff/widgets/cached_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MainPage extends StatefulWidget {
  final Widget child;
  const MainPage({super.key, required this.child});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const MethodChannel _nativeBackChannel = MethodChannel('snowfluff/back');
  static final Set<String> _mobileExitRoutes = {
    AppRouter.home,
    AppRouter.library,
    AppRouter.discover,
    AppRouter.settings,
  };
  DateTime? _lastBackPressedAt;
  DateTime? _lastBackHandledAt;
  OverlayEntry? _exitHintEntry;
  Timer? _exitHintTimer;
  late final AnimationController _exitHintAnimationController;
  Future<void> _dismissExitHint({bool animated = true}) async {
    _exitHintTimer?.cancel();
    _exitHintTimer = null;
    final entry = _exitHintEntry;
    if (entry == null) return;
    if (animated && _exitHintAnimationController.value > 0) {
      await _exitHintAnimationController.reverse();
    }
    entry.remove();
    _exitHintEntry = null;
  }
  void _showExitHint(BuildContext context) {
    final configuredThemeColor = SettingsService.themeColor;
    final configuredThemeMode = SettingsService.themeMode;
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final isDark = switch (configuredThemeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformBrightness == Brightness.dark,
    };
    final bubbleColor = Color.alphaBlend(
      configuredThemeColor.withValues(alpha: isDark ? 0.30 : 0.22),
      isDark ? const Color(0xE6141414) : const Color(0xE6282828),
    );
    final borderColor = configuredThemeColor.withValues(
      alpha: isDark ? 0.45 : 0.38,
    );
    _dismissExitHint(animated: false);
    final overlay = Overlay.of(context, rootOverlay: true);
    final fadeAnimation = CurvedAnimation(
      parent: _exitHintAnimationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _exitHintEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: 0,
          right: 0,
          bottom: 28 + MediaQuery.of(context).padding.bottom,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FadeTransition(
                opacity: fadeAnimation,
                child: Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderColor, width: 0.8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        '再按一次退出',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_exitHintEntry!);
    _exitHintAnimationController.forward(from: 0);
    _exitHintTimer = Timer(const Duration(milliseconds: 1050), () {
      _dismissExitHint();
    });
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nativeBackChannel.setMethodCallHandler(_handleNativeBackCall);
    _exitHintAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
  }

  Future<bool> _dispatchRootBackByLayout() async {
    if (!mounted) return false;
    switch (DeviceConfig.layoutMode) {
      case LayoutMode.tablet:
        await _handleAndroidTabletBack(context);
        return true;
      case LayoutMode.mobile:
        await _handleAndroidMobileBack(context);
        return true;
      case LayoutMode.desktop:
        return false;
    }
  }

  Future<dynamic> _handleNativeBackCall(MethodCall call) async {
    if (call.method != 'onBackPressed') return false;
    return _dispatchRootBackByLayout();
  }

  @override
  void dispose() {
    _nativeBackChannel.setMethodCallHandler(null);
    _dismissExitHint(animated: false);
    _exitHintAnimationController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  Future<bool> didPopRoute() async {
    return _dispatchRootBackByLayout();
  }
  Future<void> _handleAndroidTabletBack(BuildContext context) async {
    final handledNow = DateTime.now();
    if (_lastBackHandledAt != null &&
        handledNow.difference(_lastBackHandledAt!) <
            const Duration(milliseconds: 300)) {
      return;
    }
    _lastBackHandledAt = handledNow;
    // 优先收起搜索输入态/键盘，行为与点击空白处一致
    if (_SearchInputHandle.instance.clearAndCollapseIfNeeded()) {
      return;
    }
    // 非根路由先后退页面，与手机端逻辑一致
    final router = GoRouter.of(context);
    final currentPath = router.state.path;
    if (!_mobileExitRoutes.contains(currentPath)) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(AppRouter.home);
      }
      return;
    }
    final now = DateTime.now();
    if (_lastBackPressedAt == null ||
        now.difference(_lastBackPressedAt!) > const Duration(seconds: 2)) {
      _lastBackPressedAt = now;
      _showExitHint(context);
      return;
    }
    await _dismissExitHint(animated: false);
    await SystemNavigator.pop();
  }

  Future<void> _handleAndroidMobileBack(BuildContext context) async {
    final handledNow = DateTime.now();
    if (_lastBackHandledAt != null &&
        handledNow.difference(_lastBackHandledAt!) <
            const Duration(milliseconds: 300)) {
      return;
    }
    _lastBackHandledAt = handledNow;
    if (_MobileTopBarHandle.instance.clearAndCollapseIfNeeded()) {
      return;
    }
    final router = GoRouter.of(context);
    final currentPath = router.state.path;
    if (!_mobileExitRoutes.contains(currentPath)) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(AppRouter.home);
      }
      return;
    }
    final now = DateTime.now();
    if (_lastBackPressedAt == null ||
        now.difference(_lastBackPressedAt!) > const Duration(seconds: 2)) {
      _lastBackPressedAt = now;
      _showExitHint(context);
      return;
    }
    await _dismissExitHint(animated: false);
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (DeviceConfig.layoutMode) {
      LayoutMode.desktop => DesktopView(child: widget.child),
      LayoutMode.tablet => TabletView(child: widget.child),
      LayoutMode.mobile => MobileView(child: widget.child),
    };
    final scaffold = Scaffold(resizeToAvoidBottomInset: false, body: body);
    if (DeviceConfig.layoutMode == LayoutMode.tablet) {
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _handleAndroidTabletBack(context);
        },
        child: scaffold,
      );
    }
    if (DeviceConfig.layoutMode == LayoutMode.mobile) {
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _handleAndroidMobileBack(context);
        },
        child: scaffold,
      );
    }
    return BackButtonListener(
      onBackButtonPressed: () async {
        final focus = FocusManager.instance.primaryFocus;
        if (focus != null && focus.hasFocus) {
          focus.unfocus();
          return true; // 已处理返回键
        }
        return false; // 交给路由继续处理
      },
      child: scaffold,
    );
  }
}

class DesktopView extends StatelessWidget {
  final Widget child;
  const DesktopView({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Column(
        children: [
          SizedBox(height: 5.w),
          _buildTopBar(),
          SizedBox(height: 5.w),
          Expanded(
            child: Row(
              children: [
                SizedBox(width: 40.w),
                Expanded(child: child),
                SizedBox(width: 40.w),
              ],
            ),
          ),
          _buildBottomBar(context),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque, // 可点击
      child: Container(
        height: 48.w,
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 60.w),
        child: Row(
          children: [
            // 歌曲信息
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildSongInfo(),
              ),
            ),
            _buildPlayControls(),
            // 播放控制按钮
          ],
        ),
      ),
      onTap: () {
        final path = GoRouter.of(context).state.path;
        if (path == AppRouter.play) {
          context.pop();
          return;
        }
        context.push(AppRouter.play);
      },
    );
  }

  Widget _buildSongInfo() {
    return Consumer(
      builder: (context, ref, child) {
        var media = ref.watch(mediaItemProvider).value;
        // 歌词预取
        final songId = int.tryParse(media?.id ?? '') ?? 0;
        if (songId > 0) ref.watch(mediaLyricProvider(songId));
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedImage(
              imageUrl: media?.artUri.toString() ?? '',
              width: 40.w,
              height: 40.w,
              borderRadius: 5.w,
            ),
            SizedBox(width: 15.w),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media?.title ?? 'Snowfluff',
                    style: TextStyle(fontSize: 14.sp),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (media?.artist != null)
                    Text(
                      media!.artist ?? '',
                      style: TextStyle(fontSize: 12.sp),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlayControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Consumer(
          builder: (context, ref, child) {
            final isQueueOpen = ref.watch(
              currentRouterPathProvider.select((p) => p == AppRouter.playqueue),
            );
            final isFM = ref.watch(isFMModeProvider.select((s) => s.value ?? false));
            final queueActiveColor = Theme.of(
              context,
            ).colorScheme.primaryContainer;
            return IconButton(
              onPressed: isFM
                  ? null
                  : () {
                      final path = GoRouter.of(context).state.path;
                      if (path != AppRouter.playqueue) {
                        context.push(AppRouter.playqueue);
                        return;
                      }
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(AppRouter.home);
                      }
                    },
              icon: Icon(
                Icons.queue_music,
                size: 22.sp,
                color: isFM ? Theme.of(context).disabledColor : (isQueueOpen ? queueActiveColor : null),
              ),
            );
          },
        ),
        SizedBox(width: 10.w),
        Consumer(
          builder: (context, ref, child) {
            final isFM = ref.watch(isFMModeProvider.select((s) => s.value ?? false));
            return IconButton(
              onPressed: isFM
                  ? () => SnowfluffMusicHandler().personalFMTrash()
                  : () => SnowfluffMusicHandler().skipToPrevious(),
              icon: Icon(
                isFM ? Icons.thumb_down_outlined : Icons.skip_previous,
                size: isFM ? 18.sp : 22.sp,
              ),
            );
          },
        ),
        SizedBox(width: 10.w),
        Consumer(
          builder: (context, ref, child) {
            var playbackState = ref.watch(
              playbackStateProvider.select((s) => s.value?.playing ?? false),
            );
            return IconButton(
              onPressed: () => SnowfluffMusicHandler().toggle(),
              icon: Icon(
                playbackState ? Icons.pause : Icons.play_arrow,
                size: 22.sp,
              ),
            );
          },
        ),
        SizedBox(width: 10.w),
        IconButton(
          onPressed: () => SnowfluffMusicHandler().skipToNext(),
          icon: Icon(Icons.skip_next, size: 22.sp),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    final barHeight = 36.w; // 更扁平
    final sideGap = 50.w;
    return SizedBox(
      height: barHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: sideGap),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _buildNavPlaceholderButtons(barHeight),
            ),
            Align(
              alignment: Alignment.center,
              child: DesktopMenu(height: barHeight),
            ),
            // 右侧：搜索，保留右边距(由外层Padding控制)
            Align(
              alignment: Alignment.centerRight,
              child: _DesktopSearchInput(
                height: barHeight,
                expandedWidth: 240.w,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavPlaceholderButtons(double h) {
    final buttonSize = h;
    return Consumer(
      builder: (context, ref, child) {
        final history = ref.watch(routeHistoryProvider);
        final historyNotifier = ref.read(routeHistoryProvider.notifier);
        final router = ref.read(routerProvider);
        return SizedBox(
          height: h,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: history.canBack
                    ? () {
                        final location = historyNotifier.goBackLocation();
                        if (location != null) {
                          router.go(location);
                        }
                      }
                    : null,
                tooltip: 'Back',
                constraints: BoxConstraints.tightFor(
                  width: buttonSize,
                  height: buttonSize,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.arrow_back_ios_new, size: 15.sp),
              ),
              SizedBox(width: 4.w),
              IconButton(
                onPressed: history.canForward
                    ? () {
                        final location = historyNotifier.goForwardLocation();
                        if (location != null) {
                          router.go(location);
                        }
                      }
                    : null,
                tooltip: 'Forward',
                constraints: BoxConstraints.tightFor(
                  width: buttonSize,
                  height: buttonSize,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.arrow_forward_ios, size: 15.sp),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SearchInputHandle {
  _SearchInputHandle._();
  static final _SearchInputHandle instance = _SearchInputHandle._();

  _DesktopSearchInputState? _state;

  void attach(_DesktopSearchInputState state) {
    _state = state;
  }

  void detach(_DesktopSearchInputState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

  bool clearAndCollapseIfNeeded() {
    return _state?._handleAndroidBack() ?? false;
  }
}

class _DesktopSearchInput extends StatefulWidget {
  final double height;
  final double expandedWidth;
  const _DesktopSearchInput({
    required this.height,
    required this.expandedWidth,
  });

  @override
  State<_DesktopSearchInput> createState() => _DesktopSearchInputState();
}

class _DesktopSearchInputState extends State<_DesktopSearchInput>
    with WidgetsBindingObserver {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  DateTime? _lastFocusLossAt;
  bool _expanded = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
    _SearchInputHandle.instance.attach(this);
  }
  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _lastFocusLossAt = DateTime.now();
    }
    final shouldCollapse =
        !_focusNode.hasFocus && _controller.text.trim().isEmpty;
    if (shouldCollapse && _expanded) {
      setState(() => _expanded = false);
      return;
    }
    setState(() {});
  }
  void _expandAndFocus() {
    if (!_expanded) {
      setState(() => _expanded = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }
  bool _handleAndroidBack() {
    if (DeviceConfig.layoutMode != LayoutMode.tablet) return false;
    final now = DateTime.now();
    final hasFocus = _focusNode.hasFocus;
    final hasText = _controller.text.trim().isNotEmpty;
    final recentlyLostFocus =
        _lastFocusLossAt != null &&
        now.difference(_lastFocusLossAt!) < const Duration(milliseconds: 400);
    if (!hasFocus && !_expanded) {
      // 兼容Android先收起键盘再分发返回事件的时序
      return recentlyLostFocus;
    }
    // 有文本但已失焦时，不应长期吞掉返回键
    // 仅在"刚失焦"窗口内消费这次返回，避免误触退出提示
    if (!hasFocus && _expanded && hasText) {
      return recentlyLostFocus;
    }
    if (hasFocus) {
      _focusNode.unfocus();
    }
    if (_expanded && !hasText) {
      setState(() => _expanded = false);
    }
    return true;
  }
  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.state == ViewFocusState.unfocused && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }
  }
  void _clearAndCollapse() {
    _controller.clear();
    _focusNode.unfocus();
    if (_expanded) {
      setState(() => _expanded = false);
    }
  }
  @override
  void dispose() {
    _SearchInputHandle.instance.detach(this);
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFocused = _focusNode.hasFocus;
    final h = widget.height;
    final bgNormal = isDark
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.42)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.90);
    final bgFocused = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.10),
      bgNormal,
    );
    final borderColor = isFocused
        ? colorScheme.primary.withValues(alpha: isDark ? 0.85 : 0.65)
        : Colors.transparent;
    final hintColor = colorScheme.onSurfaceVariant;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: _expanded ? widget.expandedWidth : h,
      height: h,
      child: _expanded
          ? Container(
              height: h,
              padding: EdgeInsets.symmetric(horizontal: 10.w),
              decoration: BoxDecoration(
                color: isFocused ? bgFocused : bgNormal,
                borderRadius: BorderRadius.circular(h / 2),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: 8.w),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.search,
                      minLines: 1,
                      maxLines: 1,
                      cursorColor: colorScheme.primary,
                      onTapOutside: (_) => _focusNode.unfocus(),
                      onSubmitted: (value) {
                        final keyword = value.trim();
                        if (keyword.isEmpty) return;
                        if (!mounted) return;
                        final state = GoRouter.of(context).state;
                        final encodedKeyword = Uri.encodeQueryComponent(keyword);
                        final location = '${AppRouter.search}?q=$encodedKeyword';
                        final isAlreadyOnSearch =
                            state.uri.path == AppRouter.search;
                        if (isAlreadyOnSearch) {
                          context.pushReplacement(location);
                        } else {
                          context.push(location);
                        }
                        _focusNode.unfocus();
                      },
                      style: TextStyle(
                        fontSize: 15.sp,
                        height: 1.15,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search Here...',
                        hintStyle: TextStyle(
                          fontSize: 15.sp,
                          height: 1.2,
                          color: hintColor,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, child) {
                      if (value.text.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return IconButton(
                        tooltip: 'Cancel',
                        onPressed: () => _clearAndCollapse(),
                        constraints: BoxConstraints.tightFor(
                          width: h - 8.w,
                          height: h - 8.w,
                        ),
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.close, size: 16.sp, color: hintColor),
                      );
                    },
                  ),
                ],
              ),
            )
          : IconButton(
              tooltip: 'Search',
              onPressed: _expandAndFocus,
              icon: Icon(Icons.search, size: 19.sp),
              style: IconButton.styleFrom(
                minimumSize: Size(h, h),
                maximumSize: Size(h, h),
                padding: EdgeInsets.zero,
              ),
            ),
    );
  }
}

class TabletView extends StatelessWidget {
  final Widget child;
  const TabletView({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, // 避免键盘弹出时布局被挤压
      body: SafeArea(
        top: true,
        bottom: false,
        left: false,
        right: false,
        child: Column(
          children: [
            SizedBox(height: 5.w),
            _buildTopBar(),
            SizedBox(height: 5.w),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: child),
                ],
              ),
            ),
            SizedBox(height: 5.w),
            // 这里加一个进度条
            _buildBottomBar(context),
            SizedBox(height: 5.w),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final isFM = ref.watch(isFMModeProvider.select((s) => s.value ?? false));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          child: child,
          onTap: () {
            final path = GoRouter.of(context).state.path;
            if (path == AppRouter.play) {
              context.pop();
              return;
            }
            context.push(AppRouter.play);
          },
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity! > 1000) {
              if (!isFM) SnowfluffMusicHandler().skipToPrevious();
            } else if (details.primaryVelocity! < -1000) {
              SnowfluffMusicHandler().skipToNext();
            }
          },
        );
      },
      child: Container(
        height: 48.w,
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 60.w),
        child: Row(
          children: [
            // 歌曲信息
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildSongInfo(),
              ),
            ),
            _buildPlayControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildSongInfo() {
    return Consumer(
      builder: (context, ref, child) {
        final media = ref.watch(mediaItemProvider).value;
        // 歌词预取
        final songId = int.tryParse(media?.id ?? '') ?? 0;
        if (songId > 0) ref.watch(mediaLyricProvider(songId));
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedImage(
              imageUrl: media?.artUri.toString() ?? '',
              width: 40.w,
              height: 40.w,
              borderRadius: 5.w,
            ),
            SizedBox(width: 15.w),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media?.title ?? 'Snowfluff',
                    style: TextStyle(fontSize: 14.sp),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (media?.artist != null)
                    Text(
                      media!.artist ?? '',
                      style: TextStyle(fontSize: 12.sp),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlayControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Consumer(
          builder: (context, ref, child) {
            final isQueueOpen = ref.watch(
              currentRouterPathProvider.select((p) => p == AppRouter.playqueue),
            );
            final isFM = ref.watch(isFMModeProvider.select((s) => s.value ?? false));
            final queueActiveColor =
                Theme.of(context).colorScheme.primaryContainer;
            return IconButton(
              onPressed: isFM
                  ? null
                  : () {
                      final path = GoRouter.of(context).state.path;
                      if (path != AppRouter.playqueue) {
                        context.push(AppRouter.playqueue);
                        return;
                      }
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(AppRouter.home);
                      }
                    },
              icon: Icon(
                Icons.queue_music,
                size: 22.sp,
                color: isFM ? Theme.of(context).disabledColor : (isQueueOpen ? queueActiveColor : null),
              ),
            );
          },
        ),
        SizedBox(width: 10.w),
        Consumer(
          builder: (context, ref, child) {
            final isFM = ref.watch(isFMModeProvider.select((s) => s.value ?? false));
            return IconButton(
              onPressed: isFM
                  ? () => SnowfluffMusicHandler().personalFMTrash()
                  : () => SnowfluffMusicHandler().skipToPrevious(),
              icon: Icon(
                isFM ? Icons.thumb_down_outlined : Icons.skip_previous,
                size: 22.sp,
              ),
            );
          },
        ),
        SizedBox(width: 10.w),
        Consumer(
          builder: (context, ref, child) {
            var playbackState = ref.watch(
              playbackStateProvider.select((s) => s.value?.playing ?? false),
            );
            return IconButton(
              onPressed: () => SnowfluffMusicHandler().toggle(),
              icon: Icon(
                playbackState ? Icons.pause : Icons.play_arrow,
                size: 22.sp,
              ),
            );
          },
        ),
        SizedBox(width: 10.w),
        IconButton(
          onPressed: () => SnowfluffMusicHandler().skipToNext(),
          icon: Icon(Icons.skip_next, size: 22.sp),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    final barHeight = 36.w;
    final sideGap = 60.w;
    return SizedBox(
      height: barHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: sideGap),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _buildNavPlaceholderButtons(barHeight),
            ),
            Align(
              alignment: Alignment.center,
              child: TabletMenu(height: barHeight),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _DesktopSearchInput(
                height: barHeight,
                expandedWidth: 240.w,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavPlaceholderButtons(double h) {
    final buttonSize = h;
    return Consumer(
      builder: (context, ref, child) {
        final history = ref.watch(routeHistoryProvider);
        final historyNotifier = ref.read(routeHistoryProvider.notifier);
        final router = ref.read(routerProvider);
        return SizedBox(
          height: h,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: history.canBack
                    ? () {
                        final location = historyNotifier.goBackLocation();
                        if (location != null) {
                          router.go(location);
                        }
                      }
                    : null,
                tooltip: 'Back',
                constraints: BoxConstraints.tightFor(
                  width: buttonSize,
                  height: buttonSize,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.arrow_back_ios_new, size: 15.sp),
              ),
              SizedBox(width: 4.w),
              IconButton(
                onPressed: history.canForward
                    ? () {
                        final location = historyNotifier.goForwardLocation();
                        if (location != null) {
                          router.go(location);
                        }
                      }
                    : null,
                tooltip: 'Forward',
                constraints: BoxConstraints.tightFor(
                  width: buttonSize,
                  height: buttonSize,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.arrow_forward_ios, size: 15.sp),
              ),
            ],
          ),
        );
      },
    );
  }
}

class MobileView extends StatefulWidget {
  final Widget child;
  const MobileView({super.key, required this.child});

  @override
  State<MobileView> createState() => _MobileViewState();
}

class _MobileViewState extends State<MobileView>
  with SingleTickerProviderStateMixin {
  final _topBarKey = GlobalKey<_MobileTopBarSectionState>();
  late final AnimationController _playSheetController;
  bool _isPlaySheetOpen = false;
  bool _shouldBuildPlaySheet = false;

  @override
  void initState() {
    super.initState();
    _MobileTopBarHandle.instance.attach(this);
    _playSheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 400),
    );
    _playSheetController.addStatusListener(_handlePlaySheetStatusChanged);
    _shouldBuildPlaySheet = _isPlaySheetOpen;
  }

  @override
  void dispose() {
    _MobileTopBarHandle.instance.detach(this);
    _playSheetController.removeStatusListener(_handlePlaySheetStatusChanged);
    _playSheetController.dispose();
    super.dispose();
  }

  void _collapseTopBarExpandedState() {
    _topBarKey.currentState?.collapseExpandedState();
  }

  bool _handleAndroidBack() {
    if (_isPlaySheetOpen || _playSheetController.value > 0.001) {
      _closePlaySheetQuick();
      return true;
    }
    return _topBarKey.currentState?.handleAndroidBack() ?? false;
  }

  void _handlePlaySheetStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    if (_isPlaySheetOpen || !_shouldBuildPlaySheet || !mounted) return;
    setState(() {
      _shouldBuildPlaySheet = false;
    });
  }

  void _animatePlaySheetTo(double target) {
    final current = _playSheetController.value;
    if ((current - target).abs() < 0.001) return;
    _playSheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 400),
      curve: Curves.ease,
    );
  }

  void _openPlaySheet() {
    if (_isPlaySheetOpen) return;
    _isPlaySheetOpen = true;
    if (!_shouldBuildPlaySheet && mounted) {
      // 首次展开先让widget tree完成一帧构建/光栅化，再启动滑入动画
      // 避免冷构建与动画争抢同一帧而造成卡顿
      setState(() {
        _shouldBuildPlaySheet = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animatePlaySheetTo(1.0);
      });
    } else {
      // 非首次打开，直接启动动画
      _animatePlaySheetTo(1.0);
    }
  }

  void _closePlaySheetQuick() {
    if (!_isPlaySheetOpen && _playSheetController.value <= 0.001) return;
    _isPlaySheetOpen = false;
    _animatePlaySheetTo(0.0);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final barHeight = 50.w;
    final barVisualHeight = barHeight + bottomPadding;
    final contentBottomGap = barVisualHeight;
    final screenHeight = MediaQuery.of(context).size.height;
    final openTop = 0.0;
    final closedTop = (screenHeight + bottomPadding)
      .clamp(openTop + 1.0, screenHeight + bottomPadding)
      .toDouble();
    final dragRange = (closedTop - openTop).clamp(1.0, double.infinity);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            top: true,
            bottom: false,
            left: false,
            right: false,
            child: Column(
              children: [
                TapRegion(
                  onTapOutside: (_) => _collapseTopBarExpandedState(),
                  child: _MobileTopBarSection(key: _topBarKey),
                ),
                SizedBox(height: 6.w),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: contentBottomGap),
                    child: PrimaryScrollController.none(child: widget.child),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _MobileBottomBar(
              bottomInset: bottomPadding,
              onOpenPlaySheet: _openPlaySheet,
            ),
          ),
          if (_shouldBuildPlaySheet)
            AnimatedBuilder(
              animation: _playSheetController,
              child: RepaintBoundary(
                child: MobilePlayPanelCard(
                  enableHeavyContent: true,
                  onQuickCollapse: _closePlaySheetQuick,
                  collapseOnArtistNavigate: true,
                ),
              ),
              builder: (context, child) {
                final value = _playSheetController.value;
                final offsetY = (1 - value) * dragRange;
                final staticMotion =
                    _playSheetController.isAnimating &&
                    value > 0.001 &&
                    value < 0.999;
                return Positioned(
                  left: 0,
                  right: 0,
                  top: openTop,
                  bottom: 0,
                  child: Transform.translate(
                    offset: Offset(0, offsetY),
                    child: TickerMode(
                      enabled: !staticMotion,
                      child: child!,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _MobileTopBarSection extends StatefulWidget {
  const _MobileTopBarSection({super.key});

  @override
  State<_MobileTopBarSection> createState() => _MobileTopBarSectionState();
}

class _MobileTopBarSectionState extends State<_MobileTopBarSection> {
  static final _menuRoutes = [
    AppRouter.home,
    AppRouter.discover,
    AppRouter.settings,
  ];
  final _searchKey = GlobalKey<_MobileSearchInputState>();
  bool _menuExpanded = false;
  bool _searchExpanded = false;
  DateTime? _lastMenuCollapsedAt;
  String _selectedMenuRoute = AppRouter.home;

  String _resolvedMenuRoute(BuildContext context) {
    final path = GoRouter.of(context).state.path;
    if (_menuRoutes.contains(path)) {
      return path!;
    }
    return _selectedMenuRoute;
  }

  void _expandMenu() {
    if (_searchExpanded) {
      _searchKey.currentState?.collapse();
    }
    if (!_menuExpanded) {
      _lastMenuCollapsedAt = null;
      setState(() => _menuExpanded = true);
    }
  }

  void _selectMenuRoute(BuildContext context, String route) {
    final currentMenuRoute = _resolvedMenuRoute(context);
    if (route == currentMenuRoute) {
      if (_menuExpanded) {
        setState(() => _menuExpanded = false);
      }
      return;
    }
    final path = GoRouter.of(context).state.path;
    if (_searchExpanded) {
      _searchKey.currentState?.collapse();
    }
    if (path != route) {
      context.replace(route);
    }
    setState(() {
      _selectedMenuRoute = route;
      _menuExpanded = false;
      _lastMenuCollapsedAt = null;
    });
  }

  void _onSearchExpandedChanged(bool expanded) {
    if (!mounted || _searchExpanded == expanded) return;
    setState(() {
      _searchExpanded = expanded;
      if (expanded) {
        _menuExpanded = false;
      }
    });
  }

  void collapseExpandedState() {
    var needsSetState = false;
    if (_menuExpanded) {
      _menuExpanded = false;
      _lastMenuCollapsedAt = DateTime.now();
      needsSetState = true;
    }
    if (_searchExpanded) {
      _searchKey.currentState?.collapse();
    }
    if (needsSetState && mounted) {
      setState(() {});
    }
  }

  bool handleAndroidBack() {
    if (_menuExpanded) {
      setState(() => _menuExpanded = false);
      _lastMenuCollapsedAt = null;
      return true;
    }
    final now = DateTime.now();
    final menuCollapsedRecently =
        _lastMenuCollapsedAt != null &&
        now.difference(_lastMenuCollapsedAt!) < const Duration(milliseconds: 500);
    if (menuCollapsedRecently) {
      _lastMenuCollapsedAt = null;
      return true;
    }
    final searchState = _searchKey.currentState;
    final searchCanConsume = searchState?.hasBackConsumableState ?? false;
    if (searchCanConsume && (searchState?._handleAndroidBack() ?? false)) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final barHeight = 36.w;
    final sideGap = 16.w;
    final buttonGap = 10.w;
    final menuButtons = 3;
    final selectedMenuRoute = _resolvedMenuRoute(context);
    return SizedBox(
      height: barHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: sideGap),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final menuOpen = _menuExpanded && !_searchExpanded;
            final collapsedLeftWidth = barHeight;
            final expandedLeftWidth =
                (menuButtons * barHeight) + ((menuButtons - 1) * buttonGap);
            final leftWidth = menuOpen ? expandedLeftWidth : collapsedLeftWidth;
            final searchExpandedWidth =
                (constraints.maxWidth - leftWidth - buttonGap)
                    .clamp(collapsedLeftWidth, constraints.maxWidth)
                    .toDouble();
            return Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: leftWidth,
                  height: barHeight,
                  child: _MobileNavButtons(
                    height: barHeight,
                    gap: buttonGap,
                    expanded: menuOpen,
                    selectedRoute: selectedMenuRoute,
                    onExpandPressed: _expandMenu,
                    onRouteSelected: (route) {
                      _selectMenuRoute(context, route);
                    },
                  ),
                ),
                SizedBox(width: buttonGap),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _MobileSearchInput(
                      key: _searchKey,
                      height: barHeight,
                      expandedWidth: searchExpandedWidth,
                      onExpandRequest: () {
                        if (_menuExpanded) {
                          setState(() => _menuExpanded = false);
                        }
                      },
                      onExpandedChanged: _onSearchExpandedChanged,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MobileBottomBar extends ConsumerWidget {
  final double bottomInset;
  final VoidCallback onOpenPlaySheet;

  const _MobileBottomBar({
    required this.bottomInset,
    required this.onOpenPlaySheet,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFM = ref.watch(isFMModeProvider.select((s) => s.value ?? false));
    final horizontalPadding = 14.w;
    final barHeight = 50.w;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpenPlaySheet,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 600) {
          if (!isFM) SnowfluffMusicHandler().skipToPrevious();
        } else if (velocity < -600) {
          SnowfluffMusicHandler().skipToNext();
        }
      },
      child: Container(
        height: barHeight + bottomInset,
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          0,
          horizontalPadding,
          bottomInset,
        ),
        child: Row(
            children: [
              const Expanded(child: _MobileBottomSongInfo()),
              Consumer(
                builder: (context, ref, child) {
                  final isPlaying = ref.watch(
                    playbackStateProvider.select(
                      (s) => s.value?.playing ?? false,
                    ),
                  );
                  return IconButton(
                    onPressed: () => SnowfluffMusicHandler().toggle(),
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 32.sp,
                    ),
                  );
                },
              ),
            ],
          ),
      ),
    );
  }
}

class _MobileBottomSongInfo extends ConsumerWidget {
  const _MobileBottomSongInfo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageUrl = ref.watch(
      mediaItemProvider.select((s) => s.value?.artUri.toString() ?? ''),
    );
    final title = ref.watch(
      mediaItemProvider.select((s) => s.value?.title ?? 'Snowfluff'),
    );
    return Row(
      children: [
        CachedImage(
          imageUrl: imageUrl,
          width: 42.w,
          height: 42.w,
          borderRadius: 21.w,
          pWidth: 80,
          pHeight: 80,
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.sp),
          ),
        ),
      ],
    );
  }
}

class _MobileNavButtons extends StatelessWidget {
  final double height;
  final double gap;
  final bool expanded;
  final String selectedRoute;
  final VoidCallback onExpandPressed;
  final ValueChanged<String> onRouteSelected;

  const _MobileNavButtons({
    required this.height,
    required this.gap,
    required this.expanded,
    required this.selectedRoute,
    required this.onExpandPressed,
    required this.onRouteSelected,
  });

  static final _routes = [
    AppRouter.home,
    AppRouter.discover,
    AppRouter.settings,
  ];

  IconData _iconOf(String route) {
    if (route == AppRouter.home) return Icons.home;
    if (route == AppRouter.discover) return Icons.near_me;
    if (route == AppRouter.settings) return Icons.settings;
    return Icons.menu;
  }

  String _tooltipOf(String route) {
    if (route == AppRouter.home) return 'Library';
    if (route == AppRouter.discover) return 'Discover';
    if (route == AppRouter.settings) return 'Settings';
    return 'Menu';
  }

  List<String> _orderedRoutes() {
    return [selectedRoute, ..._routes.where((r) => r != selectedRoute)];
  }

  ButtonStyle _iconButtonStyle() {
    return IconButton.styleFrom(
      minimumSize: Size(height, height),
      maximumSize: Size(height, height),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      alignment: Alignment.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    final routes = _orderedRoutes();
    final iconSize = (height * 0.74).clamp(20.0, 28.0);
    return SizedBox(
      height: height,
      child: ClipRect(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    axis: Axis.horizontal,
                    axisAlignment: -1,
                    child: child,
                  ),
                );
              },
              child: expanded
                  ? Row(
                      key: const ValueKey('expanded-nav'),
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(routes.length, (index) {
                        final route = routes[index];
                        return Padding(
                          padding: EdgeInsets.only(
                            left: index == 0 ? 0 : gap,
                          ),
                          child: SizedBox(
                            width: height,
                            height: height,
                            child: Center(
                              child: IconButton(
                                tooltip: _tooltipOf(route),
                                onPressed: () => onRouteSelected(route),
                                constraints: BoxConstraints.tightFor(
                                  width: height,
                                  height: height,
                                ),
                                style: _iconButtonStyle(),
                                icon: Icon(_iconOf(route), size: iconSize),
                              ),
                            ),
                          ),
                        );
                      }),
                    )
                  : SizedBox(
                      width: height,
                      height: height,
                      child: Center(
                        child: IconButton(
                          key: const ValueKey('collapsed-nav'),
                          tooltip: _tooltipOf(selectedRoute),
                          onPressed: onExpandPressed,
                          constraints: BoxConstraints.tightFor(
                            width: height,
                            height: height,
                          ),
                          style: _iconButtonStyle(),
                          icon: Icon(_iconOf(selectedRoute), size: iconSize),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileSearchInput extends StatefulWidget {
  final double height;
  final double expandedWidth;
  final VoidCallback? onExpandRequest;
  final ValueChanged<bool>? onExpandedChanged;

  const _MobileSearchInput({
    super.key,
    required this.height,
    required this.expandedWidth,
    this.onExpandRequest,
    this.onExpandedChanged,
  });

  @override
  State<_MobileSearchInput> createState() => _MobileSearchInputState();
}

class _MobileSearchInputState extends State<_MobileSearchInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  DateTime? _lastFocusLossAt;
  bool _expanded = false;

  bool get hasBackConsumableState {
    final now = DateTime.now();
    final recentlyLostFocus =
        _lastFocusLossAt != null &&
        now.difference(_lastFocusLossAt!) < const Duration(milliseconds: 400);
    return _expanded || _focusNode.hasFocus || recentlyLostFocus;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _lastFocusLossAt = DateTime.now();
    }
    final shouldCollapse =
        !_focusNode.hasFocus && _controller.text.trim().isEmpty;
    if (shouldCollapse && _expanded) {
      setState(() => _expanded = false);
      widget.onExpandedChanged?.call(false);
      return;
    }
    setState(() {});
  }

  void _expandAndFocus() {
    widget.onExpandRequest?.call();
    if (!_expanded) {
      setState(() => _expanded = true);
      widget.onExpandedChanged?.call(true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void collapse() {
    if (!_expanded) return;
    _controller.clear();
    _focusNode.unfocus();
    setState(() => _expanded = false);
    widget.onExpandedChanged?.call(false);
  }

  bool _handleAndroidBack() {
    final now = DateTime.now();
    final hasFocus = _focusNode.hasFocus;
    final hasText = _controller.text.trim().isNotEmpty;
    final recentlyLostFocus =
        _lastFocusLossAt != null &&
        now.difference(_lastFocusLossAt!) < const Duration(milliseconds: 400);
    if (!hasFocus && !_expanded) {
      // 兼容Android先收起键盘再分发返回事件的时序
      return recentlyLostFocus;
    }
    // 有文本但已失焦时，遵循平板搜索的返回键处理窗口
    if (!hasFocus && _expanded && hasText) {
      return recentlyLostFocus;
    }
    if (hasFocus) {
      _focusNode.unfocus();
    }
    if (_expanded && !hasText) {
      setState(() => _expanded = false);
      widget.onExpandedChanged?.call(false);
    }
    return true;
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isFocused = _focusNode.hasFocus;
    final h = widget.height;
    final bgNormal = isDark
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.42)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.90);
    final bgFocused = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.10),
      bgNormal,
    );
    final borderColor = isFocused
        ? colorScheme.primary.withValues(alpha: isDark ? 0.85 : 0.65)
        : Colors.transparent;
    final hintColor = colorScheme.onSurfaceVariant;
    final collapsedIconSize = (h * 0.74).clamp(20.0, 28.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: _expanded ? widget.expandedWidth : h,
      height: h,
      child: _expanded
          ? Container(
              height: h,
              padding: EdgeInsets.symmetric(horizontal: 10.w),
              decoration: BoxDecoration(
                color: isFocused ? bgFocused : bgNormal,
                borderRadius: BorderRadius.circular(h / 2),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: 8.w),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.search,
                      minLines: 1,
                      maxLines: 1,
                      cursorColor: colorScheme.primary,
                      onTapOutside: (_) => _focusNode.unfocus(),
                      onSubmitted: (value) {
                        final keyword = value.trim();
                        if (keyword.isEmpty || !mounted) return;
                        final state = GoRouter.of(context).state;
                        final encodedKeyword = Uri.encodeQueryComponent(keyword);
                        final location = '${AppRouter.search}?q=$encodedKeyword';
                        final isAlreadyOnSearch =
                            state.uri.path == AppRouter.search;
                        if (isAlreadyOnSearch) {
                          context.pushReplacement(location);
                        } else {
                          context.push(location);
                        }
                        _focusNode.unfocus();
                      },
                      style: TextStyle(
                        fontSize: 15.sp,
                        height: 1.15,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search Here...',
                        hintStyle: TextStyle(
                          fontSize: 15.sp,
                          height: 1.2,
                          color: hintColor,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, child) {
                      if (value.text.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return IconButton(
                        tooltip: 'Cancel',
                        onPressed: collapse,
                        constraints: BoxConstraints.tightFor(
                          width: h - 8.w,
                          height: h - 8.w,
                        ),
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.close, size: 16.sp, color: hintColor),
                      );
                    },
                  ),
                ],
              ),
            )
          : IconButton(
              tooltip: 'Search',
              onPressed: _expandAndFocus,
              icon: Icon(Icons.search, size: collapsedIconSize),
              style: IconButton.styleFrom(
                minimumSize: Size(h, h),
                maximumSize: Size(h, h),
                padding: EdgeInsets.zero,
              ),
            ),
    );
  }
}

class _MobileTopBarHandle {
  _MobileTopBarHandle._();
  static final _MobileTopBarHandle instance = _MobileTopBarHandle._();
  _MobileViewState? _state;
  void attach(_MobileViewState state) {
    _state = state;
  }
  void detach(_MobileViewState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }
  bool clearAndCollapseIfNeeded() {
    return _state?._handleAndroidBack() ?? false;
  }
}
