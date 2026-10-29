// The color/typography registry mirrors lib/reading_visual_theme.dart.
// Native Form layouts choose their own composition using these shared IDs.
export interface ReadingWidgetTheme {
  id: string;
  background: string;
  foreground: string;
  muted: string;
  accent: string;
  secondary: string;
  isDark: boolean;
  prefersSerif: boolean;
}

function theme(id: string, background: string, foreground: string, muted: string,
  accent: string, secondary: string, isDark: boolean = false, prefersSerif: boolean = false): ReadingWidgetTheme {
  return {
    id: id,
    background: background,
    foreground: foreground,
    muted: muted,
    accent: accent,
    secondary: secondary,
    isDark: isDark,
    prefersSerif: prefersSerif
  };
}

export function readingWidgetTheme(id: string): ReadingWidgetTheme {
  switch (id) {
    case 'shelf':
      return theme('shelf', '#EEF4F0', '#183A30', '#5C6C63', '#3E7361', '#BED3C7');
    case 'paper':
    case 'cream':
    case 'editorial':
      return theme('editorial', '#FAF6E9', '#353126', '#6F6854', '#9B8141', '#DAD0AD', false, true);
    case 'night':
    case 'constellation':
      return theme('constellation', '#101629', '#E9EDF7', '#A5B0CD', '#B4A3F5', '#334267', true);
    case 'signal':
      return theme('signal', '#F0F1E8', '#1C292A', '#5F6F69', '#4F7E6C', '#C8D098');
    case 'score':
      return theme('score', '#FFF4F3', '#352F44', '#786275', '#C84D76', '#F0BACD');
    case 'ink':
      return theme('ink', '#F6F4E9', '#233E3B', '#607167', '#A4473A', '#B8D1C7', false, true);
    case 'festival':
      return theme('festival', '#F2F8FB', '#1B3D54', '#566F7D', '#E47843', '#AECEDF');
    case 'archive':
    default:
      return theme('archive', '#F7F8F6', '#18232C', '#66727B', '#2E769E', '#C8D9E0');
  }
}

export function readingWidgetSkin(id: string, season: number): ReadingWidgetTheme {
  const dark = id === 'night' || id === 'film';
  const accent = id === 'seasons' ? ['#AF7D8B', '#5786A2', '#B18842', '#4F8985'][season] :
    dark ? '#DCB65E' : id === 'paper' ? '#606D5D' : '#4F8985';
  return theme(id, id === 'night' ? '#101419' : id === 'film' ? '#10100F' : id === 'paper' ? '#ECECE5' : '#F4F0E6',
    dark ? '#F6F1E6' : '#272C29', dark ? '#A6A49E' : '#6F726C', accent, dark ? '#2C2F30' : '#DCD9D0', dark, id === 'paper');
}
