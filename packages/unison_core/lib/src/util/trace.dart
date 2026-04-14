/// Debug logging infrastructure.
///
/// Mirrors OCaml Unison's trace module. Category-based filtering
/// with configurable verbosity levels.
library;

/// Log level for trace messages.
enum TraceLevel {
  /// Errors that prevent sync.
  error,

  /// Warnings about potential issues.
  warning,

  /// Normal operation messages.
  info,

  /// Detailed debugging.
  debug,

  /// Very verbose — individual file operations.
  verbose,
}

/// Log category for filtering.
enum TraceCategory {
  update,
  recon,
  transport,
  remote,
  fingerprint,
  archive,
  props,
  filter,
  profile,
  fswatch,
  general,
}

/// Callback type for trace output.
typedef TraceHandler = void Function(
  TraceCategory category,
  TraceLevel level,
  String message,
);

/// Global trace configuration.
class Trace {
  static TraceLevel _minLevel = TraceLevel.info;
  static final Set<TraceCategory> _enabledCategories =
      TraceCategory.values.toSet();
  static TraceHandler _handler = _defaultHandler;

  /// Set the minimum log level.
  static set minLevel(TraceLevel level) => _minLevel = level;
  static TraceLevel get minLevel => _minLevel;

  /// Enable/disable specific categories.
  static void enableCategory(TraceCategory cat) => _enabledCategories.add(cat);
  static void disableCategory(TraceCategory cat) =>
      _enabledCategories.remove(cat);
  static void enableAllCategories() =>
      _enabledCategories.addAll(TraceCategory.values);

  /// Set a custom trace handler.
  static set handler(TraceHandler h) => _handler = h;

  /// Log a trace message.
  static void log(
    TraceCategory category,
    TraceLevel level,
    String message,
  ) {
    if (level.index > _minLevel.index) return;
    if (!_enabledCategories.contains(category)) return;
    _handler(category, level, message);
  }

  /// Convenience methods.
  static void error(TraceCategory cat, String msg) =>
      log(cat, TraceLevel.error, msg);
  static void warning(TraceCategory cat, String msg) =>
      log(cat, TraceLevel.warning, msg);
  static void info(TraceCategory cat, String msg) =>
      log(cat, TraceLevel.info, msg);
  static void debug(TraceCategory cat, String msg) =>
      log(cat, TraceLevel.debug, msg);
  static void verbose(TraceCategory cat, String msg) =>
      log(cat, TraceLevel.verbose, msg);

  static void _defaultHandler(
    TraceCategory category,
    TraceLevel level,
    String message,
  ) {
    final prefix = '[${level.name.toUpperCase()}][${category.name}]';
    // ignore: avoid_print
    print('$prefix $message');
  }
}
