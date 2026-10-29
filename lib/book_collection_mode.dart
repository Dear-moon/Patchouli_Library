/// A collection's presentation is independent from its current device budget.
/// Keep the requested mode when the runtime temporarily suppresses 3D effects.
enum BookCollectionMode {
  list,
  shelfList,
  shelfGrid,
  grid;

  bool get hasShelf => this == shelfList || this == shelfGrid;
  bool get isGrid => this == shelfGrid || this == grid;

  /// `shelf` is the existing persisted contract for shelf with a list below it.
  String get storageValue => this == shelfList ? 'shelf' : name;

  String get label => switch (this) {
    list => '纯列表',
    shelfList => '立体书架 + 列表',
    shelfGrid => '立体书架 + 宫格',
    grid => '纯宫格',
  };

  static BookCollectionMode? tryParse(Object? value) => switch (value) {
    'list' => list,
    'shelf' || 'shelfList' => shelfList,
    'shelfGrid' => shelfGrid,
    'grid' => grid,
    _ => null,
  };

  static BookCollectionMode parseOrDefault(Object? value) =>
      tryParse(value) ?? shelfList;
}

enum AppStartPage {
  discovery,
  shelf,
  local;

  String get label => switch (this) {
    discovery => '发现',
    shelf => '书架',
    local => '本地',
  };

  static AppStartPage? tryParse(Object? value) => switch (value) {
    'discovery' => discovery,
    'shelf' => shelf,
    'local' => local,
    _ => null,
  };

  static AppStartPage parseOrDefault(Object? value) =>
      tryParse(value) ?? discovery;
}
