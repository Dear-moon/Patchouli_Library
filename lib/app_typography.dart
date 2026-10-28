enum AppTypeface {
  system('系统字体', null),
  sourceHanSerif('思源宋体', 'SourceHanSerifCN'),
  sourceHanSans('思源黑体', 'WenkuSourceHanSansCN'),
  lxgwWenKai('霞鹜文楷屏幕版', 'WenkuLXGWWenKaiScreen'),
  zhuqueFangsong('朱雀仿宋', 'WenkuZhuqueFangsong'),
  iansui('芫荽', 'WenkuIansui');

  const AppTypeface(this.label, this.family);
  final String label;
  final String? family;
  static AppTypeface fromRecord(Object? value) =>
      AppTypeface.values.where((font) => font.name == value).firstOrNull ??
      AppTypeface.system;
}
