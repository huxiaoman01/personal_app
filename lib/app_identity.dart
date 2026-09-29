/// app 的身份标识。
///
/// 名字只有这一处出处：改名字时改 [displayName] 就行，导出文件名、备份包里
/// 的标识、报错文案都跟着变。
///
/// 注：安卓桌面图标下的名字在 `android/app/src/main/AndroidManifest.xml`
/// 的 `android:label` 里，那份是 XML，没法跟这里共用常量，改名时两边都要改。
abstract final class AppIdentity {
  /// 界面上、文件名里显示的名字。
  static const String displayName = '可可嫑记';

  /// 备份包 `data.json` 里写进 `app` 字段的标识。
  static const String backupId = displayName;

  /// 改过名字之前，备份包里写的是这些。
  ///
  /// 导入时必须一并认下来——否则你自己在旧版本上导出的备份，
  /// 到了新版本会被告知「不是本 app 导出的」，那备份就白做了。
  static const List<String> legacyBackupIds = <String>['万能百宝箱'];

  /// 这个标识是不是本 app 的（含改名前的老标识）。
  static bool acceptsBackupId(String id) =>
      id == backupId || legacyBackupIds.contains(id);
}
