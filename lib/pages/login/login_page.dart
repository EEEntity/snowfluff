// 登录页面

import 'dart:io';
import 'package:snowfluff/common/user_info_store.dart';
import 'package:snowfluff/router/app_router.dart';
import 'package:snowfluff/utils/device_config.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:ncm_api/api/agent.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  // 用于手动输入Cookie的控件
  final TextEditingController cookieController = TextEditingController();
  bool isLoading = false; // 是否正在加载

  void _showToast(String? message) {
    final text = message?.trim() ?? '';
    if (text.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0XFF1ED760);
    return switch (DeviceConfig.layoutMode) {
      LayoutMode.desktop => _DesktopLoginPage(
        cookieController: cookieController,
        isLoading: isLoading,
        primaryColor: primaryColor,
        onLogin: () => _handleCookieLogin(cookieController.text),
        onPickFile: _pickCookieFile,
      ),
      LayoutMode.tablet => _TabletLoginPage(
        cookieController: cookieController,
        isLoading: isLoading,
        primaryColor: primaryColor,
        onLogin: () => _handleCookieLogin(cookieController.text),
        onPickFile: _pickCookieFile,
      ),
      LayoutMode.mobile => _MobileLoginPage(
        cookieController: cookieController,
        isLoading: isLoading,
        primaryColor: primaryColor,
        onLogin: () => _handleCookieLogin(cookieController.text),
        onPickFile: _pickCookieFile,
      ),
    };
  }
  // 统一的登录逻辑处理
  void _handleCookieLogin(String rawCookie) async {
    if (rawCookie.trim().isEmpty) {
      _showToast("Cookie cannot be empty");
      return;
    }
    setState(() => isLoading = true);
    try {
      // 1. 解析 Cookie 字符串
      List<Cookie> cookies = _parseCookieString(
        rawCookie.split('\n').first.trim(),
      );
      // 2. 注入到 SnowfluffMusicManager 的 CookieJar 中
      final uri = Uri.parse("https://music.163.com");
      await SnowfluffMusicManager.cookieJar.saveFromResponse(uri, cookies);
      // 3. 验证 Cookie 是否有效：调用获取用户信息接口
      var userInfo = await SnowfluffMusicManager().userInfo();
      if (userInfo != null && userInfo.profile != null) {
        // 4. 持久化最小用户信息到 Hive（user_info）
        await UserInfoStore().saveFromProfile(userInfo.profile!);
        if (mounted) {
          _showToast("Login Success: ${userInfo.profile?.nickname}");
          context.replace(AppRouter.home);
        }
      } else {
        _showToast("Login failed: Invalid or expired Cookie");
      }
    } catch (e) {
      _showToast("Error: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // 文件选择逻辑
  Future<void> _pickCookieFile() async {
    if (isLoading) return;
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.any, // Linux 下如果识别不了后缀可以选 any
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        String content = await file.readAsString();
        _handleCookieLogin(content);
      }
    } catch (e) {
      _showToast("Failed to read file: $e");
    }
  }

  // 解析逻辑
  List<Cookie> _parseCookieString(String cookieString) {
    List<Cookie> cookies = [];
    final pairs = cookieString.split(';');
    for (var pair in pairs) {
      final index = pair.indexOf('=');
      if (index != -1) {
        final key = pair.substring(0, index).trim();
        final value = pair.substring(index + 1).trim();
        if (key.isNotEmpty) {
          // 编码处理
          cookies.add(Cookie(key, Uri.encodeComponent(value)));
        }
      }
    }
    return cookies;
  }
  @override
  void dispose() {
    cookieController.dispose();
    super.dispose();
  }
}

class _DesktopLoginPage extends StatelessWidget {
  final TextEditingController cookieController;
  final bool isLoading;
  final Color primaryColor;
  final VoidCallback onLogin;
  final VoidCallback onPickFile;

  const _DesktopLoginPage({
    required this.cookieController,
    required this.isLoading,
    required this.primaryColor,
    required this.onLogin,
    required this.onPickFile,
  });

  @override
  Widget build(BuildContext context) {
    return _DesktopTabletLoginPage(
      cookieController: cookieController,
      isLoading: isLoading,
      primaryColor: primaryColor,
      onLogin: onLogin,
      onPickFile: onPickFile,
      usePointerCursor: true,
      enableRipple: false,
      dismissKeyboardOnTap: false,
    );
  }
}

class _TabletLoginPage extends StatelessWidget {
  final TextEditingController cookieController;
  final bool isLoading;
  final Color primaryColor;
  final VoidCallback onLogin;
  final VoidCallback onPickFile;

  const _TabletLoginPage({
    required this.cookieController,
    required this.isLoading,
    required this.primaryColor,
    required this.onLogin,
    required this.onPickFile,
  });

  @override
  Widget build(BuildContext context) {
    return _DesktopTabletLoginPage(
      cookieController: cookieController,
      isLoading: isLoading,
      primaryColor: primaryColor,
      onLogin: onLogin,
      onPickFile: onPickFile,
      usePointerCursor: false,
      enableRipple: true,
      dismissKeyboardOnTap: true,
    );
  }
}

class _DesktopTabletLoginPage extends StatelessWidget {
  final TextEditingController cookieController;
  final bool isLoading;
  final Color primaryColor;
  final VoidCallback onLogin;
  final VoidCallback onPickFile;
  final bool usePointerCursor;
  final bool enableRipple;
  final bool dismissKeyboardOnTap;

  const _DesktopTabletLoginPage({
    required this.cookieController,
    required this.isLoading,
    required this.primaryColor,
    required this.onLogin,
    required this.onPickFile,
    required this.usePointerCursor,
    required this.enableRipple,
    required this.dismissKeyboardOnTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: dismissKeyboardOnTap
            ? () => FocusManager.instance.primaryFocus?.unfocus()
            : null,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = (constraints.maxWidth * 0.88)
                .clamp(360.w, 1000.w)
                .toDouble();
            final contentHeight = (constraints.maxHeight * 0.84)
                .clamp(420.h, 620.h)
                .toDouble();

            return Center(
              child: SizedBox(
                width: contentWidth,
                height: contentHeight,
                child: Padding(
                  padding: EdgeInsets.all(28.w),
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 2,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cookie, size: 72.w),
                                  SizedBox(height: 12.h),
                                  Text(
                                    'Snowfluff Music',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 30.sp,
                                        ),
                                  ),
                                  SizedBox(height: 32.h),
                                  if (isLoading)
                                    CircularProgressIndicator(
                                      color: primaryColor,
                                    )
                                  else
                                    Column(
                                      children: [
                                        _LoginActionButton(
                                          onPressed: onLogin,
                                          icon: Icons.send,
                                          label: 'Login',
                                          color: primaryColor,
                                          usePointerCursor: usePointerCursor,
                                          enableRipple: enableRipple,
                                        ),
                                        SizedBox(height: 14.h),
                                        _LoginActionButton(
                                          onPressed: onPickFile,
                                          icon: Icons.attach_file,
                                          label: 'Select File',
                                          color: Colors.blueGrey.withValues(alpha: 0.8),
                                          usePointerCursor: usePointerCursor,
                                          enableRipple: enableRipple,
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            VerticalDivider(
                              indent: 36.h,
                              endIndent: 36.h,
                              color: Colors.grey.withValues(alpha: 0.2),
                            ),
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 30.w),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Paste cookies:',
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: 10.h),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).hoverColor,
                                        borderRadius: BorderRadius.circular(
                                          12.w,
                                        ),
                                        border: Border.all(
                                          color: Colors.grey.withValues(alpha: 0.1),
                                        ),
                                      ),
                                      child: TextField(
                                        controller: cookieController,
                                        maxLines: 12,
                                        minLines: 12,
                                        cursorColor: primaryColor,
                                        decoration: InputDecoration(
                                          hintText: 'k=v, k=v',
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.all(14.w),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: 14.h),
                        child: Text(
                          '用本地Cookie进行登录',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MobileLoginPage extends StatelessWidget {
  final TextEditingController cookieController;
  final bool isLoading;
  final Color primaryColor;
  final VoidCallback onLogin;
  final VoidCallback onPickFile;

  const _MobileLoginPage({
    required this.cookieController,
    required this.isLoading,
    required this.primaryColor,
    required this.onLogin,
    required this.onPickFile,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = (constraints.maxWidth * 0.08)
                  .clamp(16.w, 32.w)
                  .toDouble();
              final verticalPadding = (constraints.maxHeight * 0.05)
                  .clamp(14.h, 30.h)
                  .toDouble();

              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Snowfluff Music',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 30.sp,
                          ),
                    ),
                    SizedBox(height: 20.h),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).hoverColor,
                        borderRadius: BorderRadius.circular(12.w),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                      ),
                      child: TextField(
                        controller: cookieController,
                        minLines: 6,
                        maxLines: 6,
                        cursorColor: primaryColor,
                        decoration: InputDecoration(
                          hintText: 'k=v, k=v',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(14.w),
                        ),
                      ),
                    ),
                    SizedBox(height: 18.h),
                    if (isLoading)
                      Padding(
                        padding: EdgeInsets.only(top: 8.h),
                        child: Center(
                          child: CircularProgressIndicator(color: primaryColor),
                        ),
                      )
                    else ...[
                      _LoginActionButton(
                        onPressed: onLogin,
                        icon: Icons.send,
                        label: 'Login',
                        color: primaryColor,
                        usePointerCursor: false,
                        enableRipple: true,
                        isFullWidth: true,
                      ),
                      SizedBox(height: 12.h),
                      _LoginActionButton(
                        onPressed: onPickFile,
                        icon: Icons.attach_file,
                        label: 'Select File',
                        color: Colors.blueGrey.withValues(alpha: 0.8),
                        usePointerCursor: false,
                        enableRipple: true,
                        isFullWidth: true,
                      ),
                    ],
                    const Spacer(),
                    Text(
                      '用本地Cookie进行登录',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LoginActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color color;
  final bool usePointerCursor;
  final bool enableRipple;
  final bool isFullWidth;

  const _LoginActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.color,
    required this.usePointerCursor,
    required this.enableRipple,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.w)),
      textStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp),
      enabledMouseCursor: usePointerCursor
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      disabledMouseCursor: SystemMouseCursors.basic,
      splashFactory: enableRipple ? null : NoSplash.splashFactory,
    );

    final style = enableRipple
        ? baseStyle
        : baseStyle.copyWith(
            overlayColor: WidgetStateProperty.resolveWith(
              (_) => Colors.transparent,
            ),
            shadowColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(0),
          );

    final button = SizedBox(
      width: isFullWidth ? double.infinity : 240.w,
      height: 48.h,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 19.w),
        label: Text(label),
        style: style,
      ),
    );

    if (!usePointerCursor) return button;
    return MouseRegion(cursor: SystemMouseCursors.click, child: button);
  }
}
