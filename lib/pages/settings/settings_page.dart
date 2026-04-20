// 设置页面

import 'dart:io';
import 'package:snowfluff/common/local_proxy_service.dart';
import 'package:snowfluff/common/media_cache_service.dart';
import 'package:snowfluff/common/settings_service.dart';
import 'package:snowfluff/pages/play/provider.dart';
import 'package:snowfluff/pages/provider.dart';
import 'package:snowfluff/utils/device_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

const Map<SongUrlLevel, String> _levelNames = {
  SongUrlLevel.standard: '标准音质',
  SongUrlLevel.exhigh: '极高音质',
  SongUrlLevel.lossless: '无损音质',
  SongUrlLevel.hires: 'Hi-Res',
  SongUrlLevel.jyeffect: '高清鲸云',
  SongUrlLevel.sky: '沉浸环绕',
  SongUrlLevel.jymaster: '超清母带',
};

class _ThemeColorOption {
  final String name;
  final Color color;
  const _ThemeColorOption(this.name, this.color);
}

const List<_ThemeColorOption> _themeColorOptions = [
  _ThemeColorOption('蓝色', Color(0xFF03A9F4)),
  _ThemeColorOption('绿色', Color(0xFF1ED760)),
  _ThemeColorOption('深橙', Color(0xFFFF5722)),
  _ThemeColorOption('粉色', Color(0xFFE91E63)),
  _ThemeColorOption('青绿', Color(0xFF009688)),
  _ThemeColorOption('琥珀', Color(0xFFFFC107)),
  _ThemeColorOption('靛蓝', Color(0xFF3F51B5)),
  _ThemeColorOption('棕色', Color(0xFF795548)),
];

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return switch (DeviceConfig.layoutMode) {
      LayoutMode.desktop => const DesktopSettingsPage(),
      LayoutMode.tablet => const TabletSettingsPage(),
      LayoutMode.mobile => const MobileSettingsPage(),
    };
  }
}

class DesktopSettingsPage extends StatelessWidget {
  const DesktopSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SettingsContent(horizontalPadding: 16);
  }
}

class TabletSettingsPage extends StatelessWidget {
  const TabletSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _SettingsContent(horizontalPadding: 60.w);
  }
}

class MobileSettingsPage extends StatelessWidget {
  const MobileSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SettingsContent(horizontalPadding: 16, useCardLayout: true);
  }
}

class _SettingsContent extends StatefulWidget {
  final double horizontalPadding;
  final bool useCardLayout;
  const _SettingsContent({
    required this.horizontalPadding,
    this.useCardLayout = false,
  });

  @override
  State<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<_SettingsContent> {
  bool _enableCache = SettingsService.cacheEnabled;
  bool _filterInstrumental = SettingsService.filterInstrumentalLyrics;
  CacheStats? _cacheStats;
  bool _cacheBusy = false;

  @override
  void initState() {
    super.initState();
    _refreshCacheStats();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> content = widget.useCardLayout
        ? _buildMobileSections()
        : _buildDesktopTabletSections();

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              // 水平内边距由外层提供
              padding: EdgeInsets.symmetric(
                horizontal: widget.horizontalPadding,
              ),
              sliver: SliverList(delegate: SliverChildListDelegate(content)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDesktopTabletSections() {
    return [
      // 界面外观标题
      _buildSectionTitle('界面外观'),
      // 深色模式行(左对齐标题，右侧平铺的ChoiceChip)
      _buildThemeSelector(),
      // 音质选择
      _buildPopupMenu(),
      // 主题色彩
      _buildColorPicker(),
      // 过滤纯音乐歌词(实验性)
      _buildFilterInstrumentalSwitch(),
      const Divider(height: 1, thickness: 1),
      // 存储与缓存
      _buildSectionTitle('存储与缓存'),
      _buildCacheSwitch(),
      _buildCacheLimit(),
      _buildCacheUsage(),
      _buildClearCacheButton(),
      const Divider(height: 1, thickness: 1),
      // 关于
      _buildSectionTitle('关于'),
      _buildAuthorTile(),
      _buildVersionTile(),
      _buildAboutTile('开源许可', 'MIT License'),
    ];
  }

  List<Widget> _buildMobileSections() {
    return [
      SizedBox(height: 8.w),
      _buildSectionCard([
        _buildThemeSelector(),
        _buildPopupMenu(),
        _buildColorPicker(),
        _buildFilterInstrumentalSwitch(),
      ], title: '界面外观'),
      SizedBox(height: 8.w),
      _buildSectionCard([
        _buildCacheSwitch(),
        _buildCacheLimit(),
        _buildCacheUsage(),
        _buildClearCacheButton(),
      ], title: '存储与缓存'),
      SizedBox(height: 8.w),
      _buildSectionCard([
        _buildAuthorTile(),
        _buildVersionTile(),
        _buildAboutTile('开源许可', 'MIT License'),
      ], title: '关于'),
      SizedBox(height: 8.w),
    ];
  }

  // 节标题(仅上下间距，不包含水平内边距)
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 12.0),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w900,
          fontSize: 26,
          letterSpacing: -0.8,
        ),
      ),
    );
  }

  Widget _buildSectionCard(List<Widget> children, {required String title}) {
    final dividerColor = Theme.of(context).dividerColor.withValues(alpha: 0.2);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12.w, 10.w, 12.w, 8.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Theme.of(context).hintColor,
                fontWeight: FontWeight.w600,
                fontSize: 14.sp,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(height: 8.w),
            ...children,
          ],
        ),
      ),
    );
  }

  // 通用行构造：左右两端靠边、垂直居中、可选点击
  Widget _row({
    required Widget left,
    Widget? right,
    double? height,
    VoidCallback? onTap,
  }) {
    final double realHeight = height ?? 48.w;
    final row = SizedBox(
      height: realHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧文本或控件，靠左
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: left),
          ),
          if (right != null)
            Align(alignment: Alignment.centerRight, child: right),
        ],
      ),
    );

    if (onTap != null) {
      // 包一层 Material + InkWell 提供点击反馈
      return Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: row),
      );
    }
    return row;
  }

  // 各行实现
  Widget _buildThemeSelector() {
    return Consumer(
      builder: (context, ref, _) {
        final mode = ref.watch(themeModeProvider);
        final chips = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            ChoiceChip(
              label: const Text('浅色'),
              selected: mode == ThemeMode.light,
              onSelected: (_) => ref
                  .read(themeModeProvider.notifier)
                  .setTheme(ThemeMode.light),
            ),
            ChoiceChip(
              label: const Text('深色'),
              selected: mode == ThemeMode.dark,
              onSelected: (_) =>
                  ref.read(themeModeProvider.notifier).setTheme(ThemeMode.dark),
            ),
            ChoiceChip(
              label: const Text('跟随系统'),
              selected: mode == ThemeMode.system,
              onSelected: (_) => ref
                  .read(themeModeProvider.notifier)
                  .setTheme(ThemeMode.system),
            ),
          ],
        );

        return _row(
          left: Text('深色模式', style: TextStyle(fontSize: 16.sp)),
          right: chips,
        );
      },
    );
  }

  Widget _buildPopupMenu() {
    final currentLevel = SettingsService.musicQuality;
    return _row(
      left: Text('音质选择', style: TextStyle(fontSize: 16.sp)),
      right: ActionChip(
        label: Text(
          _levelNames[currentLevel]!,
          style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w500),
        ),
        onPressed: () async {
          final selected = await showGeneralDialog<SongUrlLevel?>(
            context: context,
            barrierDismissible: true,
            barrierLabel: '选择音质',
            barrierColor: Colors.black54,
            transitionDuration: const Duration(milliseconds: 200),
            pageBuilder: (ctx, a1, a2) {
              return Center(
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 420),
                      child: RadioGroup<SongUrlLevel>(
                        groupValue: currentLevel,
                      onChanged: (SongUrlLevel? v) => Navigator.of(ctx).pop(v),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shrinkWrap: true,
                          children: SongUrlLevel.values.map((l) {
                            return RadioListTile<SongUrlLevel>(
                              title: Text(_levelNames[l]!),
                              value: l,
                            );
                          }).toList(),
                        ),
                      ),
                  ),
                ),
              );
            },
            transitionBuilder: (ctx, anim, secAnim, child) {
              return FadeTransition(
                opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
                child: child,
              );
            },
          );
          if (selected != null) {
            await SettingsService.setMusicQuality(selected);
            if (!mounted) return;
            FocusScope.of(context).unfocus();
            setState(() {});
          }
        },
      ),
    );
  }

  Widget _buildColorPicker() {
    return Consumer(
      builder: (context, ref, _) {
        final selectedColor = ref.watch(themeColorProvider);

        return _row(
          left: Text('主题色彩', style: TextStyle(fontSize: 16.sp)),
          right: ActionChip(
            avatar: CircleAvatar(backgroundColor: selectedColor, radius: 10),
            label: Text(
              _colorNameOf(selectedColor),
              style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w500),
            ),
            onPressed: () => _showThemeColorDialog(ref, selectedColor),
          ),
        );
      },
    );
  }

  String _formatHex(Color color) {
    final hex = color
        .toARGB32()
        .toRadixString(16)
        .toUpperCase()
        .padLeft(8, '0');
    return '0x$hex';
  }

  String _colorNameOf(Color color) {
    for (final item in _themeColorOptions) {
      if (item.color.toARGB32() == color.toARGB32()) {
        return item.name;
      }
    }
    return _formatHex(color);
  }

  Future<void> _showThemeColorDialog(WidgetRef ref, Color selectedColor) async {
    final selected = await showGeneralDialog<_ThemeColorOption?>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '选择主题色',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, a1, a2) {
        return Center(
            child: Material(
              color: Theme.of(ctx).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shrinkWrap: true,
                  children: _themeColorOptions.map((item) {
                    final isSelected =
                        item.color.toARGB32() == selectedColor.toARGB32();

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: item.color,
                        radius: 12,
                      ),
                      title: Text(item.name),
                      subtitle: Text(_formatHex(item.color)),
                      trailing: isSelected
                          ? Icon(
                              Icons.check,
                              color: Theme.of(ctx).colorScheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.of(ctx).pop(item),
                    );
                  }).toList(),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, secAnim, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        );
      },
    );

    if (selected != null &&
        selected.color.toARGB32() != selectedColor.toARGB32()) {
      await ref.read(themeColorProvider.notifier).setColor(selected.color);
    }
  }

  Widget _buildFilterInstrumentalSwitch() {
    return Consumer(
      builder: (context, ref, _) {
        return _row(
          left: Text('过滤纯音乐歌词(exp)', style: TextStyle(fontSize: 16.sp)),
          right: Switch.adaptive(
            value: _filterInstrumental,
            onChanged: (bool v) async {
              await SettingsService.setFilterInstrumentalLyrics(v);
              // 使所有已缓存的歌词 provider 失效，立刻以新规则重新解析
              ref.invalidate(mediaLyricProvider);
              setState(() => _filterInstrumental = v);
            },
          ),
        );
      },
    );
  }

  Widget _buildCacheSwitch() {
    return _row(
      left: Text('自动缓存', style: TextStyle(fontSize: 16.sp)),
      right: Switch.adaptive(
        value: _enableCache,
        onChanged: (bool v) async {
          await SettingsService.setCacheEnabled(v);
          setState(() => _enableCache = v);
        },
      ),
    );
  }

  Widget _buildCacheLimit() {
    final int bytes = SettingsService.cacheMaxBytes;
    return _row(
      left: Text('缓存上限', style: TextStyle(fontSize: 16.sp)),
      right: ActionChip(
        label: Text(
          _formatLimit(bytes),
          style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w500),
        ),
        onPressed: _showCacheLimitDialog,
      ),
    );
  }

  Widget _buildCacheUsage() {
    final String text;
    if (_cacheStats == null) {
      text = _cacheBusy ? '读取中...' : '--';
    } else {
      text =
          '${_formatBytes(_cacheStats!.usedBytes)} / ${_formatBytes(_cacheStats!.maxBytes)}';
    }
    return _row(
      left: Text('当前占用', style: TextStyle(fontSize: 16.sp)),
      right: Text(
        text,
        style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13.sp),
      ),
    );
  }

  Widget _buildClearCacheButton() {
    return _row(
      left: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '清理缓存',
            style: TextStyle(color: Colors.redAccent, fontSize: 16.sp),
          ),
          // SizedBox(width: 12),
          // Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
        ],
      ),
      onTap: _showDeleteDialog,
    );
  }

  Future<void> _refreshCacheStats() async {
    if (!mounted) return;
    setState(() {
      _cacheBusy = true;
    });
    try {
      final CacheStats stats = await MediaCacheService().getStats();
      if (!mounted) return;
      setState(() {
        _cacheStats = stats;
      });
    } finally {
      if (mounted) {
        setState(() {
          _cacheBusy = false;
        });
      }
    }
  }

  Future<void> _showCacheLimitDialog() async {
    final List<int> options = <int>[
      1 * 1024 * 1024 * 1024,
      2 * 1024 * 1024 * 1024,
      4 * 1024 * 1024 * 1024,
      8 * 1024 * 1024 * 1024,
      16 * 1024 * 1024 * 1024,
    ];
    final int current = SettingsService.cacheMaxBytes;

    final int? selected = await showGeneralDialog<int?>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '选择缓存上限',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, a1, a2) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Center(
            child: Material(
              color: Theme.of(ctx).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: RadioGroup<int>(
                  groupValue: current,
                  onChanged: (int? value) => Navigator.of(ctx).pop(value),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shrinkWrap: true,
                    children: options
                        .map((int value) {
                          return RadioListTile<int>(
                            value: value,
                            title: Text(_formatLimit(value)),
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, secAnim, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        );
      },
    );

    if (selected == null || selected == current) return;
    await SettingsService.setCacheMaxBytes(selected);
    await MediaCacheService().pruneIfNeeded();
    await _refreshCacheStats();
    if (!mounted) return;
    setState(() {});
  }

  String _formatLimit(int bytes) {
    final double gb = bytes / (1024 * 1024 * 1024);
    if (gb % 1 == 0) {
      return '${gb.toInt()} GB';
    }
    return '${gb.toStringAsFixed(1)} GB';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    if (unit == 0) return '${value.toInt()} ${units[unit]}';
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unit]}';
  }

  Widget _buildAuthorTile() {
    return _row(
      left: Text('作者', style: TextStyle(fontSize: 16.sp)),
      right: Text('EEEntity', style: TextStyle(color: Colors.grey, fontSize: 14.sp)),
      onTap: () => _showLinkDialog(
        title: '联系作者',
        content: '发送邮件？',
        url: 'mailto:eeentity@hotmail.com',
      ),
    );
  }

  Widget _buildVersionTile() {
    return _row(
      left: Text('当前版本', style: TextStyle(fontSize: 16.sp)),
      right: Text('0.1.0+1', style: TextStyle(color: Colors.grey, fontSize: 14.sp)),
      onTap: () => _showLinkDialog(
        title: '查看版本',
        content: '前往 GitHub 查看发布记录？',
        url: 'https://github.com/EEEntity/snowfluff/releases',
      ),
    );
  }

  Widget _buildAboutTile(String title, String info) {
    return _row(
      left: Text(title, style: TextStyle(fontSize: 16.sp)),
      right: Text(
        info,
        style: TextStyle(color: Colors.grey, fontSize: 14.sp),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    try {
      if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', url]);
      } else {
        // Android / iOS: 需要 url_launcher，此处降级提示
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(url)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开链接')),
      );
    }
  }

  void _showLinkDialog({
    required String title,
    required String content,
    required String url,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(context);
              _openUrl(url);
            },
            child: const Text('继续'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清理？'),
        content: const Text('这将删除所有本地已缓存的音乐/图片/歌词，但不会影响用户数据'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () async {
              Navigator.pop(context);
              await MediaCacheService().clearAll();
              await _refreshCacheStats();
              if (!mounted) return;
              ScaffoldMessenger.of(
                this.context,
              ).showSnackBar(const SnackBar(content: Text('缓存已清理')));
            },
            child: const Text('确认清理'),
          ),
        ],
      ),
    );
  }
}
