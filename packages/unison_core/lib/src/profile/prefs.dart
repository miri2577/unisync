/// Typed preference registry.
///
/// Mirrors OCaml Unison's preference system. Each preference has a name,
/// type, default value, category, and documentation string.
library;

/// Preference category for UI grouping.
enum PrefCategory {
  basic,
  sync,
  remote,
  backup,
  filter,
  ui,
  advanced,
  expert,
}

/// Optional validator for preference values.
typedef PrefValidator<T> = String? Function(T value);

/// A single typed preference.
class Pref<T> {
  final String name;
  final String doc;
  final PrefCategory category;
  final T defaultValue;
  final bool cliOnly;
  final PrefValidator<T>? validator;

  T _value;
  bool _isSet = false;

  Pref({
    required this.name,
    required this.doc,
    required this.defaultValue,
    this.category = PrefCategory.basic,
    this.cliOnly = false,
    this.validator,
  }) : _value = defaultValue;

  /// Current value (or default if never set).
  T get value => _value;

  /// Set the value. Returns validation error or null if valid.
  String? setValue(T v) {
    if (validator != null) {
      final error = validator!(v);
      if (error != null) return error;
    }
    _value = v;
    _isSet = true;
    return null;
  }

  /// Set the value (throws on validation failure).
  set value(T v) {
    final error = setValue(v);
    if (error != null) {
      throw ArgumentError('Invalid value for $name: $error');
    }
  }

  /// Whether this preference was explicitly set.
  bool get isSet => _isSet;

  /// Reset to default.
  void reset() {
    _value = defaultValue;
    _isSet = false;
  }

  @override
  String toString() => '$name = $_value';
}

/// A list preference that accumulates values.
class ListPref extends Pref<List<String>> {
  ListPref({
    required super.name,
    required super.doc,
    super.category,
    super.cliOnly,
  }) : super(defaultValue: const []);

  /// Add a value to the list.
  void add(String v) {
    if (!isSet) {
      value = [v];
    } else {
      value = [...value, v];
    }
  }

  @override
  void reset() {
    super.reset();
    value = [];
  }
}

/// Central preference registry.
class PrefsRegistry {
  final Map<String, Pref> _prefs = {};

  /// Register a boolean preference.
  Pref<bool> createBool({
    required String name,
    required String doc,
    bool defaultValue = false,
    PrefCategory category = PrefCategory.basic,
    bool cliOnly = false,
  }) {
    final p = Pref<bool>(
      name: name,
      doc: doc,
      defaultValue: defaultValue,
      category: category,
      cliOnly: cliOnly,
    );
    _prefs[name] = p;
    return p;
  }

  /// Register an integer preference.
  Pref<int> createInt({
    required String name,
    required String doc,
    int defaultValue = 0,
    PrefCategory category = PrefCategory.basic,
  }) {
    final p = Pref<int>(
      name: name,
      doc: doc,
      defaultValue: defaultValue,
      category: category,
    );
    _prefs[name] = p;
    return p;
  }

  /// Register a string preference.
  Pref<String> createString({
    required String name,
    required String doc,
    String defaultValue = '',
    PrefCategory category = PrefCategory.basic,
    bool cliOnly = false,
  }) {
    final p = Pref<String>(
      name: name,
      doc: doc,
      defaultValue: defaultValue,
      category: category,
      cliOnly: cliOnly,
    );
    _prefs[name] = p;
    return p;
  }

  /// Register a string list preference (accumulating).
  ListPref createStringList({
    required String name,
    required String doc,
    PrefCategory category = PrefCategory.basic,
  }) {
    final p = ListPref(
      name: name,
      doc: doc,
      category: category,
    );
    _prefs[name] = p;
    return p;
  }

  /// Get a preference by name.
  Pref? get(String name) => _prefs[name];

  /// Set a preference from a string value (parsed based on type).
  ///
  /// Returns a validation error string, or null if successful.
  /// Returns 'unknown preference' if name is not registered.
  String? setFromString(String name, String value) {
    final pref = _prefs[name];
    if (pref == null) return 'Unknown preference: $name';

    try {
      if (pref is ListPref) {
        pref.add(value);
      } else if (pref is Pref<bool>) {
        final boolVal = switch (value.toLowerCase()) {
          'true' || 'yes' || '1' => true,
          'false' || 'no' || '0' => false,
          _ => throw FormatException('Invalid boolean: $value'),
        };
        pref.value = boolVal;
      } else if (pref is Pref<int>) {
        final intVal = int.tryParse(value);
        if (intVal == null) {
          return 'Invalid integer for $name: $value';
        }
        pref.value = intVal;
      } else if (pref is Pref<String>) {
        pref.value = value;
      }
      return null;
    } on ArgumentError catch (e) {
      return e.message?.toString();
    } on FormatException catch (e) {
      return e.message;
    }
  }

  /// Reset all preferences to defaults.
  void resetAll() {
    for (final p in _prefs.values) {
      p.reset();
    }
  }

  /// All registered preference names.
  Iterable<String> get names => _prefs.keys;

  /// All registered preferences.
  Iterable<Pref> get all => _prefs.values;

  /// All preferences in a category.
  Iterable<Pref> byCategory(PrefCategory cat) =>
      _prefs.values.where((p) => p.category == cat);

  /// Serialize all set preferences to key=value lines.
  String serialize() {
    final buf = StringBuffer();
    for (final p in _prefs.values) {
      if (!p.isSet) continue;
      if (p is ListPref) {
        for (final v in p.value) {
          buf.writeln('${p.name} = $v');
        }
      } else {
        buf.writeln('${p.name} = ${p.value}');
      }
    }
    return buf.toString();
  }
}
