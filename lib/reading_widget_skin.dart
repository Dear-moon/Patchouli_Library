import 'package:flutter/material.dart';

/// Decoration is independent of content. Null/old snapshots retain their look.
enum ReadingWidgetSkin {
  original('原有配色'),
  seasons('四季手帐'),
  archive('读者档案'),
  night('夜读之城'),
  film('胶片三幕'),
  paper('剪纸');

  const ReadingWidgetSkin(this.label);
  final String label;
  static const available = [seasons, archive, night, film, paper];
  static ReadingWidgetSkin fromId(String? id) =>
      values.where((value) => value.name == id).firstOrNull ?? original;

  Color get background => switch (this) {
    night => const Color(0xFF101419),
    film => const Color(0xFF10100F),
    paper => const Color(0xFFECECE5),
    _ => const Color(0xFFF4F0E6),
  };
  Color get ink => switch (this) {
    night || film => const Color(0xFFF6F1E6),
    _ => const Color(0xFF272C29),
  };
  Color accent(DateTime date) => switch (this) {
    seasons => seasonColors[seasonIndex(date)],
    night || film => const Color(0xFFDCB65E),
    paper => const Color(0xFF606D5D),
    _ => const Color(0xFF4F8985),
  };
}

const seasonColors = [
  Color(0xFFAF7D8B),
  Color(0xFF5786A2),
  Color(0xFFB18842),
  Color(0xFF4F8985),
];
int seasonIndex(DateTime date) => switch (date.month) {
  >= 3 && <= 5 => 0,
  >= 6 && <= 8 => 1,
  >= 9 && <= 11 => 2,
  _ => 3,
};
String seasonName(DateTime date) => ['春', '夏', '秋', '冬'][seasonIndex(date)];

/// A goal is opt-in. Zero disables it; valid goals are 1..1440 minutes/day.
int readingDailyGoal(int? minutes) =>
    minutes != null && minutes >= 1 && minutes <= 1440 ? minutes : 0;
String readingGoalCaption(int goal, int? seconds) {
  if (goal == 0) return '';
  if (seconds == null) return '每日目标 $goal 分钟';
  final remaining = ((goal * 60 - seconds) / 60).ceil();
  return remaining <= 0 ? '今日目标已达成' : '目标 $goal 分 · 还差 $remaining 分';
}
