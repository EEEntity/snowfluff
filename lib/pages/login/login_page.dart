// 登录页面

import 'dart:async';
import 'dart:io';
import 'package:snowfluff/common/user_info_store.dart';
import 'package:snowfluff/router/app_router.dart';
import 'package:snowfluff/utils/device_config.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:ncm_api/api/agent.dart';
import 'package:qr_flutter/qr_flutter.dart';

enum _LoginMode {
  cookie,
  sms,
  qrcode 
}
enum _QrStatus {
  idle,
  loading,
  waiting,
  confirming,
  success,
  expired,
  error
}

const _kPrimaryColor = Color(0XFF1ED760);

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  // 用于手动输入的控件
  final TextEditingController cookieController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController captchaController = TextEditingController();

  _LoginMode _mode = _LoginMode.cookie;
  bool isLoading = false; // sms/cookies登录的加载状态
  bool _smsCodeLoading = false; // 获取验证码的加载状态
  int _smsCooldown = 0;
  Timer? _cooldownTimer;
  _QrStatus _qrStatus = _QrStatus.idle; // QR 码状态
  String? _qrKey;
  String? _qrUrl;
  Timer? _qrPollTimer;

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

  void _handleCookieLogin(String rawCookie) async {
    if (rawCookie.trim().isEmpty) {
      _showToast("Cookie cannot be empty");
      return;
    }
    setState(() => isLoading = true);
    try {
      final cookies = _parseCookieString(
        rawCookie.split('\n').first.trim(),
      );
      final uri = Uri.parse("https://music.163.com");
      await SnowfluffMusicManager.cookieJar.saveFromResponse(uri, cookies);
      await _verifyAndNavigate();
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
      final result = await FilePicker.pickFiles(
        type: FileType.any,
      );
      if (result != null && result.files.single.path != null) {
        final content = await File(result.files.single.path!).readAsString();
        _handleCookieLogin(content);
      }
    } catch (e) {
      _showToast("Failed to read file: $e");
    }
  }

  // 解析逻辑
  List<Cookie> _parseCookieString(String cookieString) {
    final cookies = <Cookie>[];
    for (final pair in cookieString.split(';')) {
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

  void _handleSendSms() async {
    final phone = phoneController.text.trim();
    if (phone.isEmpty) {
      _showToast('请输入手机号');
      return;
    }
    setState(() => _smsCodeLoading = true);
    try {
      final result = await SnowfluffMusicManager().sendSmsCode(phone: phone);
      if (result?.code == 200) {
        _showToast('验证码已发送');
        _startCooldown();
      } else {
        _showToast('发送失败: ${result?.message}');
      }
    } catch (e) {
      _showToast('Error: $e');
    } finally {
      if (mounted) setState(() => _smsCodeLoading = false);
    }
  }

  void _handleSmsLogin() async {
    final phone = phoneController.text.trim();
    final captcha = captchaController.text.trim();
    if (phone.isEmpty || captcha.isEmpty) {
      _showToast('请填写手机号和验证码');
      return;
    }
    setState(() => isLoading = true);
    try {
      final result = await SnowfluffMusicManager().loginCellPhone(
        phone: phone,
        captcha: captcha,
      );
      if (result?.code == 200) {
        await _verifyAndNavigate();
      } else {
        _showToast('登录失败: code=${result?.code}');
      }
    } catch (e) {
      _showToast('Error: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _smsCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _smsCooldown--;
        if (_smsCooldown <= 0) t.cancel();
      });
    });
  }

  void _onModeChange(_LoginMode m) {
    if (_mode == _LoginMode.qrcode && m != _LoginMode.qrcode) {
      _stopQrPolling();
    }
    setState(() => _mode = m);
    if (m == _LoginMode.qrcode) _handleQrModeEnter();
  }

  void _handleQrModeEnter() {
    if (_qrStatus == _QrStatus.idle ||
        _qrStatus == _QrStatus.expired ||
        _qrStatus == _QrStatus.error) {
      _loadQrCode();
    }
  }

  Future<void> _loadQrCode() async {
    _stopQrPolling();
    setState(() => _qrStatus = _QrStatus.loading);
    try {
      final keyResult = await SnowfluffMusicManager().qrCodeKey();
      if (!mounted) return;
      if (keyResult?.code != 200 || (keyResult?.unikey.isEmpty ?? true)) {
        setState(() => _qrStatus = _QrStatus.error);
        return;
      }
      _qrKey = keyResult!.unikey;
      _qrUrl = SnowfluffMusicManager().qrCode(key: _qrKey!);
      setState(() => _qrStatus = _QrStatus.waiting);
      _startQrPolling();
    } catch (e) {
      if (mounted) setState(() => _qrStatus = _QrStatus.error);
    }
  }

  void _startQrPolling() {
    _stopQrPolling();
    _qrPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_qrKey == null || !mounted) return;
      try {
        final result =
            await SnowfluffMusicManager().checkQrCode(key: _qrKey!);
        if (!mounted) return;
        switch (result?.code) {
          case 801:
            setState(() => _qrStatus = _QrStatus.waiting);
          case 802:
            setState(() => _qrStatus = _QrStatus.confirming);
          case 803:
            _stopQrPolling();
            setState(() => _qrStatus = _QrStatus.success);
            await _verifyAndNavigate();
          case 800:
            _stopQrPolling();
            setState(() => _qrStatus = _QrStatus.expired);
          default:
            break;
        }
      } catch (_) {}
    });
  }

  void _stopQrPolling() {
    _qrPollTimer?.cancel();
    _qrPollTimer = null;
  }

  Future<void> _verifyAndNavigate() async {
    final userInfo = await SnowfluffMusicManager().userInfo();
    if (userInfo != null && userInfo.profile != null) {
      await UserInfoStore().saveFromProfile(userInfo.profile!);
      if (mounted) {
        _showToast('Login Success: ${userInfo.profile?.nickname}');
        context.replace(AppRouter.home);
      }
    } else {
      _showToast('Login failed: Invalid or expired credentials');
    }
  }

  @override
  void dispose() {
    cookieController.dispose();
    phoneController.dispose();
    captchaController.dispose();
    _cooldownTimer?.cancel();
    _stopQrPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (DeviceConfig.layoutMode) {
      LayoutMode.desktop => _DesktopTabletLoginShell(
          mode: _mode,
          onModeChange: _onModeChange,
          usePointerCursor: true,
          enableRipple: false,
          dismissKeyboardOnTap: false,
          cookieContent: _CookieRightPane(
            cookieController: cookieController,
            onPickFile: _pickCookieFile,
          ),
          smsContent: _SmsRightPane(
            phoneController: phoneController,
            captchaController: captchaController,
            smsCodeLoading: _smsCodeLoading,
            smsCooldown: _smsCooldown,
            onSendSms: _handleSendSms,
          ),
          qrcodeContent: _QrcodeRightPane(
            status: _qrStatus,
            qrUrl: _qrUrl,
          ),
          leftButtons: _leftButtons(usePointerCursor: true, enableRipple: false),
        ),
      LayoutMode.tablet => _DesktopTabletLoginShell(
          mode: _mode,
          onModeChange: _onModeChange,
          usePointerCursor: false,
          enableRipple: true,
          dismissKeyboardOnTap: true,
          cookieContent: _CookieRightPane(
            cookieController: cookieController,
            onPickFile: _pickCookieFile,
          ),
          smsContent: _SmsRightPane(
            phoneController: phoneController,
            captchaController: captchaController,
            smsCodeLoading: _smsCodeLoading,
            smsCooldown: _smsCooldown,
            onSendSms: _handleSendSms,
          ),
          qrcodeContent: _QrcodeRightPane(
            status: _qrStatus,
            qrUrl: _qrUrl,
          ),
          leftButtons: _leftButtons(usePointerCursor: false, enableRipple: true),
        ),
      LayoutMode.mobile => _MobileLoginPage(
          mode: _mode,
          onModeChange: _onModeChange,
          isLoading: isLoading,
          cookieController: cookieController,
          phoneController: phoneController,
          captchaController: captchaController,
          smsCooldown: _smsCooldown,
          smsCodeLoading: _smsCodeLoading,
          qrStatus: _qrStatus,
          qrUrl: _qrUrl,
          onCookieLogin: () => _handleCookieLogin(cookieController.text),
          onPickFile: _pickCookieFile,
          onSendSms: _handleSendSms,
          onSmsLogin: _handleSmsLogin,
          onQrRefresh: _loadQrCode,
        ),
    };
  }

  Widget _leftButtons({
    required bool usePointerCursor,
    required bool enableRipple,
  }) {
    if (isLoading) {
      return CircularProgressIndicator(color: _kPrimaryColor);
    }
    return switch (_mode) {
      _LoginMode.cookie => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LoginActionButton(
              onPressed: () => _handleCookieLogin(cookieController.text),
              icon: Icons.send,
              label: 'Login',
              color: _kPrimaryColor,
              usePointerCursor: usePointerCursor,
              enableRipple: enableRipple,
            ),
            SizedBox(height: 14.h),
            _LoginActionButton(
              onPressed: _pickCookieFile,
              icon: Icons.attach_file,
              label: 'Select File',
              color: Colors.blueGrey.withValues(alpha: 0.8),
              usePointerCursor: usePointerCursor,
              enableRipple: enableRipple,
            ),
          ],
        ),
      _LoginMode.sms => _LoginActionButton(
          onPressed: _handleSmsLogin,
          icon: Icons.send,
          label: 'Login',
          color: _kPrimaryColor,
          usePointerCursor: usePointerCursor,
          enableRipple: enableRipple,
        ),
      _LoginMode.qrcode => _LoginActionButton(
          onPressed: (_qrStatus == _QrStatus.expired ||
                  _qrStatus == _QrStatus.error ||
                  _qrStatus == _QrStatus.idle)
              ? _loadQrCode
              : null,
          icon: Icons.refresh,
          label: 'Refresh',
          color: Colors.blueGrey.withValues(alpha: 0.8),
          usePointerCursor: usePointerCursor,
          enableRipple: enableRipple,
        ),
    };
  }
}

class _DesktopTabletLoginShell extends StatelessWidget {
  final _LoginMode mode;
  final ValueChanged<_LoginMode> onModeChange;
  final bool usePointerCursor;
  final bool enableRipple;
  final bool dismissKeyboardOnTap;
  final Widget cookieContent;
  final Widget smsContent;
  final Widget qrcodeContent;
  final Widget leftButtons;

  const _DesktopTabletLoginShell({
    required this.mode,
    required this.onModeChange,
    required this.usePointerCursor,
    required this.enableRipple,
    required this.dismissKeyboardOnTap,
    required this.cookieContent,
    required this.smsContent,
    required this.qrcodeContent,
    required this.leftButtons,
  });

  IconData get _modeIcon => switch (mode) {
        _LoginMode.cookie => Icons.cookie,
        _LoginMode.sms => Icons.sms,
        _LoginMode.qrcode => Icons.qr_code,
      };

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
                                Icon(_modeIcon, size: 72.w),
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
                                leftButtons,
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
                            child: switch (mode) {
                              _LoginMode.cookie => cookieContent,
                              _LoginMode.sms => smsContent,
                              _LoginMode.qrcode => qrcodeContent,
                            },
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: 14.h),
                      child: _ModeSwitcher(
                        current: mode,
                        onChanged: onModeChange,
                        usePointerCursor: usePointerCursor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _CookieRightPane extends StatelessWidget {
  final TextEditingController cookieController;
  final VoidCallback onPickFile;

  const _CookieRightPane({
    required this.cookieController,
    required this.onPickFile,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
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
              cursorColor: _kPrimaryColor,
              decoration: InputDecoration(
                hintText: 'k=v; k=v',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(14.w),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmsRightPane extends StatelessWidget {
  final TextEditingController phoneController;
  final TextEditingController captchaController;
  final bool smsCodeLoading;
  final int smsCooldown;
  final VoidCallback onSendSms;

  const _SmsRightPane({
    required this.phoneController,
    required this.captchaController,
    required this.smsCodeLoading,
    required this.smsCooldown,
    required this.onSendSms,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 30.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _inputLabel('手机号'),
          SizedBox(height: 8.h),
          _InputBox(
            child: Row(
              children: [
                Text(
                  '+86',
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(width: 8.w),
                Container(width: 1, height: 18.h, color: Colors.grey.shade300),
                SizedBox(width: 8.w),
                Expanded(
                  child: TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    cursorColor: _kPrimaryColor,
                    decoration: InputDecoration(
                      hintText: '请输入手机号',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          _inputLabel('验证码'),
          SizedBox(height: 8.h),
          _InputBox(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: captchaController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    cursorColor: _kPrimaryColor,
                    decoration: InputDecoration(
                      hintText: '请输入验证码',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                      isDense: true,
                    ),
                  ),
                ),
                _SendCodeButton(
                  cooldown: smsCooldown,
                  isLoading: smsCodeLoading,
                  onPressed: onSendSms,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputLabel(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 14.sp,
      fontWeight: FontWeight.w500
    ),
  );
}

class _QrcodeRightPane extends StatelessWidget {
  final _QrStatus status;
  final String? qrUrl;

  const _QrcodeRightPane({required this.status, this.qrUrl});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: switch (status) {
        _QrStatus.loading => const CircularProgressIndicator(
            color: _kPrimaryColor,
          ),
        _QrStatus.waiting => qrUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12.w),
                child: QrImageView(
                  data: qrUrl!,
                  size: 180.w,
                  backgroundColor: Colors.white,
                ),
              )
            : const SizedBox.shrink(),
        _QrStatus.confirming => _qrStatusText('待确认'),
        _QrStatus.success => _qrStatusText('扫码成功'),
        _QrStatus.expired => _qrStatusText('已失效', grey: true),
        _QrStatus.error => _qrStatusText('加载失败', grey: true),
        _QrStatus.idle => const SizedBox.shrink(),
      },
    );
  }

  Widget _qrStatusText(String text, {bool grey = false}) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 16.sp,
        fontWeight: FontWeight.w500,
        color: grey ? Colors.grey.shade500 : null,
      ),
    );
  }
}

class _MobileLoginPage extends StatelessWidget {
  final _LoginMode mode;
  final ValueChanged<_LoginMode> onModeChange;
  final bool isLoading;
  final TextEditingController cookieController;
  final TextEditingController phoneController;
  final TextEditingController captchaController;
  final int smsCooldown;
  final bool smsCodeLoading;
  final _QrStatus qrStatus;
  final String? qrUrl;
  final VoidCallback onCookieLogin;
  final VoidCallback onPickFile;
  final VoidCallback onSendSms;
  final VoidCallback onSmsLogin;
  final VoidCallback onQrRefresh;

  const _MobileLoginPage({
    required this.mode,
    required this.onModeChange,
    required this.isLoading,
    required this.cookieController,
    required this.phoneController,
    required this.captchaController,
    required this.smsCooldown,
    required this.smsCodeLoading,
    required this.qrStatus,
    this.qrUrl,
    required this.onCookieLogin,
    required this.onPickFile,
    required this.onSendSms,
    required this.onSmsLogin,
    required this.onQrRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
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
                  SizedBox(height: 24.h),
                  // 当前模式内容
                  _mobileContent(context),
                  SizedBox(height: 20.h),
                  // 操作按钮
                  if (isLoading)
                    Center(child: CircularProgressIndicator(color: _kPrimaryColor))
                  else
                    _mobileButtons(context),
                  SizedBox(height: 24.h),
                  // 分割线
                  const Divider(),
                  SizedBox(height: 12.h),
                  _ModeSwitcher(
                    current: mode,
                    onChanged: onModeChange,
                    usePointerCursor: false,
                  ),
                  SizedBox(height: 8.h),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _mobileContent(BuildContext context) {
    return switch (mode) {
      _LoginMode.cookie => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                cursorColor: _kPrimaryColor,
                decoration: InputDecoration(
                  hintText: 'k=v; k=v',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(14.w),
                ),
              ),
            ),
          ],
        ),
      _LoginMode.sms => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InputBox(
              child: Row(children: [
                Text(
                    '+86',
                    style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500)
                ),
                SizedBox(width: 8.w),
                Container(
                    width: 1, height: 18.h, color: Colors.grey.shade300),
                SizedBox(width: 8.w),
                Expanded(
                  child: TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    cursorColor: _kPrimaryColor,
                    decoration: InputDecoration(
                      hintText: '请输入手机号',
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 14.h),
                      isDense: true,
                    ),
                  ),
                ),
              ]),
            ),
            SizedBox(height: 12.h),
            _InputBox(
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: captchaController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    cursorColor: _kPrimaryColor,
                    decoration: InputDecoration(
                      hintText: '请输入验证码',
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 14.h),
                      isDense: true,
                    ),
                  ),
                ),
                _SendCodeButton(
                  cooldown: smsCooldown,
                  isLoading: smsCodeLoading,
                  onPressed: onSendSms,
                ),
              ]),
            ),
          ],
        ),
      _LoginMode.qrcode => Center(
          child: switch (qrStatus) {
            _QrStatus.loading => const CircularProgressIndicator(
                color: _kPrimaryColor,
              ),
            _QrStatus.waiting => qrUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12.w),
                    child: QrImageView(
                      data: qrUrl!,
                      size: 200.w,
                      backgroundColor: Colors.white,
                    ),
                  )
                : const SizedBox.shrink(),
            _QrStatus.confirming => Text('待确认',
                style: TextStyle(
                    fontSize: 16.sp, fontWeight: FontWeight.w500)),
            _QrStatus.success => Text('扫码成功',
                style: TextStyle(
                    fontSize: 16.sp, fontWeight: FontWeight.w500)),
            _QrStatus.expired => Text('已失效',
                style: TextStyle(
                    fontSize: 16.sp, color: Colors.grey.shade500)),
            _QrStatus.error => Text('加载失败',
                style: TextStyle(
                    fontSize: 16.sp, color: Colors.grey.shade500)),
            _QrStatus.idle => const SizedBox.shrink(),
          },
        ),
    };
  }

  Widget _mobileButtons(BuildContext context) {
    return switch (mode) {
      _LoginMode.cookie => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LoginActionButton(
              onPressed: onCookieLogin,
              icon: Icons.send,
              label: 'Login',
              color: _kPrimaryColor,
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
        ),
      _LoginMode.sms => _LoginActionButton(
          onPressed: onSmsLogin,
          icon: Icons.send,
          label: 'Login',
          color: _kPrimaryColor,
          usePointerCursor: false,
          enableRipple: true,
          isFullWidth: true,
        ),
      _LoginMode.qrcode => _LoginActionButton(
          onPressed: (qrStatus == _QrStatus.expired ||
                  qrStatus == _QrStatus.error ||
                  qrStatus == _QrStatus.idle)
              ? onQrRefresh
              : null,
          icon: Icons.refresh,
          label: 'Refresh',
          color: Colors.blueGrey.withValues(alpha: 0.8),
          usePointerCursor: false,
          enableRipple: true,
          isFullWidth: true,
        ),
    };
  }
}

/// 统一的输入框容器
class _InputBox extends StatelessWidget {
  final Widget child;
  const _InputBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: Theme.of(context).hoverColor,
        borderRadius: BorderRadius.circular(12.w),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: child,
    );
  }
}

/// 获取验证码按钮(带倒计时)
class _SendCodeButton extends StatelessWidget {
  final int cooldown;
  final bool isLoading;
  final VoidCallback onPressed;

  const _SendCodeButton({
    required this.cooldown,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final canSend = cooldown <= 0 && !isLoading;
    return TextButton(
      onPressed: canSend ? onPressed : null,
      style: TextButton.styleFrom(
        foregroundColor: _kPrimaryColor,
        padding: EdgeInsets.symmetric(horizontal: 8.w),
      ),
      child: Text(
        cooldown > 0 ? '${cooldown}s' : '获取验证码',
        style: TextStyle(fontSize: 13.sp),
      ),
    );
  }
}

/// 底部模式切换器
class _ModeSwitcher extends StatelessWidget {
  final _LoginMode current;
  final ValueChanged<_LoginMode> onChanged;
  final bool usePointerCursor;

  const _ModeSwitcher({
    required this.current,
    required this.onChanged,
    required this.usePointerCursor,
  });

  static const _modes = [
    (_LoginMode.sms, '短信验证码'),
    (_LoginMode.qrcode, '二维码'),
    (_LoginMode.cookie, 'Cookies'),
  ];

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < _modes.length; i++) {
      final (mode, label) = _modes[i];
      final isCurrent = mode == current;

      if (i > 0) {
        items.add(Text(
          ' · ',
          style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade400),
        ));
      }

      final textWidget = Text(
        label,
        style: TextStyle(
          fontSize: 13.sp,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          color: isCurrent
              ? Theme.of(context).colorScheme.onSurface
              : Colors.grey.shade500,
        ),
      );

      if (isCurrent) {
        items.add(textWidget);
      } else {
        final btn = GestureDetector(
          onTap: () => onChanged(mode),
          child: textWidget,
        );
        items.add(
          usePointerCursor
              ? MouseRegion(cursor: SystemMouseCursors.click, child: btn)
              : btn,
        );
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Text(
        //   '登录方式:   ',
        //   style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade500),
        // ),
        ...items,
      ],
    );
  }
}

class _LoginActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
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
