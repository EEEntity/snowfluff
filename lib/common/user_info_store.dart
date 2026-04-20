import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:ncm_api/api/user.dart';

class CachedUserInfo {
  final int uid;
  final String avatarUrl;
  final String nickname;
  final String signature;
  final int updatedAtMs;

  const CachedUserInfo.empty()
    : uid = 0,
      avatarUrl = '',
      nickname = '',
      signature = '',
      updatedAtMs = 0;

  const CachedUserInfo({
    required this.uid,
    required this.avatarUrl,
    required this.nickname,
    required this.signature,
    required this.updatedAtMs,
  });

  factory CachedUserInfo.fromProfile(
    UserInfoProfile profile, {
    int? updatedAtMs,
  }) {
    return CachedUserInfo(
      uid: profile.userId,
      avatarUrl: profile.avatarUrl,
      nickname: profile.nickname,
      signature: profile.signature,
      updatedAtMs: updatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  bool sameCore(CachedUserInfo other) {
    return uid == other.uid &&
        avatarUrl == other.avatarUrl &&
        nickname == other.nickname &&
        signature == other.signature;
  }
}

class UserInfoStore {
  static const String _boxName = 'user_info';
  static const String _uidKey = 'uid';
  static const String _avatarUrlKey = 'avatarUrl';
  static const String _nicknameKey = 'nickname';
  static const String _signatureKey = 'signature';
  static const String _updatedAtMsKey = 'updatedAtMs';

  Future<Box<dynamic>> _box() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<dynamic>(_boxName);
    }
    return Hive.openBox<dynamic>(_boxName);
  }

  Future<CachedUserInfo?> read() async {
    final box = await _box();

    final int uid = _readInt(box, _uidKey);
    if (uid <= 0) return null;

    return CachedUserInfo(
      uid: uid,
      avatarUrl: _readString(box, _avatarUrlKey),
      nickname: _readString(box, _nicknameKey),
      signature: _readString(box, _signatureKey),
      updatedAtMs: _readInt(box, _updatedAtMsKey),
    );
  }

  Future<int> readUid() async {
    final box = await _box();
    return _readInt(box, _uidKey);
  }

  Future<bool> saveFromProfile(UserInfoProfile profile) async {
    if (profile.userId <= 0) return false;
    return save(CachedUserInfo.fromProfile(profile));
  }

  Future<bool> save(CachedUserInfo next) async {
    if (next.uid <= 0) return false;
    final box = await _box();

    final prev = CachedUserInfo(
      uid: _readInt(box, _uidKey),
      avatarUrl: _readString(box, _avatarUrlKey),
      nickname: _readString(box, _nicknameKey),
      signature: _readString(box, _signatureKey),
      updatedAtMs: _readInt(box, _updatedAtMsKey),
    );
    final changed = !prev.sameCore(next);
    await box.put(_uidKey, next.uid);
    await box.put(_avatarUrlKey, next.avatarUrl);
    await box.put(_nicknameKey, next.nickname);
    await box.put(_signatureKey, next.signature);
    await box.put(_updatedAtMsKey, next.updatedAtMs);
    return changed;
  }

  int _readInt(Box<dynamic> box, String key, {int defaultValue = 0}) {
    final dynamic value = box.get(key, defaultValue: defaultValue);
    return value is int ? value : defaultValue;
  }

  String _readString(Box<dynamic> box, String key, {String defaultValue = ''}) {
    final dynamic value = box.get(key, defaultValue: defaultValue);
    return value is String ? value : defaultValue;
  }
}
