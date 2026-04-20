import 'package:snowfluff/common/local_proxy_service.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class SettingsService {
  static const String _boxName = 'app_settings';
  static const String _keyMusicQuality = 'music_quality';
  static const String _keyThemeColor = 'theme_color';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyCacheEnabled = 'cache_enabled';
  static const String _keyCacheMaxBytes = 'cache_max_bytes';
  static const String _keyFilterInstrumentalLyrics = 'filter_instrumental_lyrics';
  static const String _keyCacheAudioPercent = 'cache_audio_percent';
  static const String _keyCacheImagePercent = 'cache_image_percent';
  static const String _keyCacheLyricPercent = 'cache_lyric_percent';

  static const int defaultCacheMaxBytes = 4 * 1024 * 1024 * 1024;

  static Future<void> init() async {
    // 如果为枚举写了Adapter，在这里注册
    // Hive.registerAdapter(SongUrlLevelAdapter());
    await Hive.openBox(_boxName);
  }

  // 获取音质(默认标准)
  static SongUrlLevel get musicQuality {
    final box = Hive.box(_boxName);
    final String name = box.get(
      _keyMusicQuality,
      defaultValue: SongUrlLevel.standard.name,
    );
    return SongUrlLevel.values.firstWhere(
      (e) => e.name == name,
      orElse: () => SongUrlLevel.standard, // 数据损坏时的兜底
    );
  }

  // 保存音质
  static Future<void> setMusicQuality(SongUrlLevel level) async {
    final box = Hive.box(_boxName);
    await box.put(_keyMusicQuality, level.name);
  }

  // 获取主题色(带默认值)
  static Color get themeColor {
    final box = Hive.box(_boxName);
    final int colorValue = box.get(
      _keyThemeColor,
      defaultValue: 0xFF03A9F4,
    ); // 默认蓝色
    return Color(colorValue);
  }

  // 保存主题色
  static Future<void> setThemeColor(Color color) async {
    final box = Hive.box(_boxName);
    await box.put(_keyThemeColor, color.toARGB32());
  }

  // 获取主题模式(默认跟随系统)
  static ThemeMode get themeMode {
    final box = Hive.box(_boxName);
    final String name = box.get(
      _keyThemeMode,
      defaultValue: ThemeMode.system.name,
    );
    return ThemeMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => ThemeMode.system,
    );
  }

  // 保存主题模式
  static Future<void> setThemeMode(ThemeMode mode) async {
    final box = Hive.box(_boxName);
    await box.put(_keyThemeMode, mode.name);
  }

  static bool get cacheEnabled {
    final box = Hive.box(_boxName);
    return box.get(_keyCacheEnabled, defaultValue: true) as bool;
  }

  static Future<void> setCacheEnabled(bool enabled) async {
    final box = Hive.box(_boxName);
    await box.put(_keyCacheEnabled, enabled);
  }

  static bool get filterInstrumentalLyrics {
    final box = Hive.box(_boxName);
    return box.get(_keyFilterInstrumentalLyrics, defaultValue: false) as bool;
  }

  static Future<void> setFilterInstrumentalLyrics(bool enabled) async {
    final box = Hive.box(_boxName);
    await box.put(_keyFilterInstrumentalLyrics, enabled);
  }

  static int get cacheMaxBytes {
    final box = Hive.box(_boxName);
    final int raw =
        box.get(_keyCacheMaxBytes, defaultValue: defaultCacheMaxBytes) as int;
    return raw > 0 ? raw : defaultCacheMaxBytes;
  }

  static Future<void> setCacheMaxBytes(int value) async {
    if (value <= 0) return;
    final box = Hive.box(_boxName);
    await box.put(_keyCacheMaxBytes, value);
  }

  static int get cacheAudioPercent {
    final box = Hive.box(_boxName);
    final int raw = box.get(_keyCacheAudioPercent, defaultValue: 78) as int;
    return raw.clamp(0, 100).toInt();
  }

  static int get cacheImagePercent {
    final box = Hive.box(_boxName);
    final int raw = box.get(_keyCacheImagePercent, defaultValue: 20) as int;
    return raw.clamp(0, 100).toInt();
  }

  static int get cacheLyricPercent {
    final box = Hive.box(_boxName);
    final int raw = box.get(_keyCacheLyricPercent, defaultValue: 2) as int;
    return raw.clamp(0, 100).toInt();
  }

  static Future<void> setCachePercentages({
    required int audio,
    required int image,
    required int lyric,
  }) async {
    final int sum = audio + image + lyric;
    if (sum <= 0) return;
    final box = Hive.box(_boxName);
    await box.put(_keyCacheAudioPercent, audio.clamp(0, 100));
    await box.put(_keyCacheImagePercent, image.clamp(0, 100));
    await box.put(_keyCacheLyricPercent, lyric.clamp(0, 100));
  }
}
