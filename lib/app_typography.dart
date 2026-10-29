enum AppTypeface {
  system('系统字体', null),
  sourceHanSerif('思源宋体', 'SourceHanSerifCN'),
  sourceHanSans('思源黑体', 'WenkuSourceHanSansCN'),
  lxgwWenKai('霞鹜文楷屏幕版', 'WenkuLXGWWenKaiScreen'),
  zhuqueFangsong('朱雀仿宋', 'WenkuZhuqueFangsong'),
  iansui('芫荽', 'WenkuIansui'),
  lxgwZhenKai('霞鹜臻楷', 'WenkuLXGWZhenKai'),
  lxgwMarkerGothic('霞鹜漫黑', 'WenkuLXGWMarkerGothic'),
  xiaolai('小赖', 'WenkuXiaolai'),
  yozai('悠哉', 'WenkuYozai'),
  sourceHanSerifTW('思源宋体 · 繁体', 'WenkuSourceHanSerifTW'),
  sourceHanSansTW('思源黑体 · 繁体', 'WenkuSourceHanSansTW'),
  lxgwWenKaiTC('霞鹜文楷 TC', 'WenkuLXGWWenKaiTC'),
  openHuninn('jf open 粉圆', 'WenkuOpenHuninn');

  const AppTypeface(this.label, this.family);
  final String label;
  final String? family;
  static AppTypeface fromRecord(Object? value) =>
      AppTypeface.values.where((font) => font.name == value).firstOrNull ??
      AppTypeface.system;
}
