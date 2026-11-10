// ignore_for_file: public_member_api_docs

/// Renders the Liquid subset that Pipes accepts in native text, with the same
/// results as the native SDKs and the WebView Liquid renderer.
class MeiroInAppNativeText {
  static final RegExp _output = RegExp(
    r'''\{\{\s*((?:attributes|profile)(?:\.[A-Za-z_][\w-]*|\[\d+\]|\["[^"\]]+"\]|\['[^'\]]+'\])+)\s*(?:\|\s*default\s*:\s*("[^"]*"|'[^']*')\s*)?\}\}''',
  );
  static final RegExp _segment = RegExp(
    r'''\.([A-Za-z_][\w-]*)|\[(\d+)\]|\["([^"\]]+)"\]|\['([^'\]]+)'\]''',
  );

  static String render(String text, Map<String, Object?> profile) =>
      text.replaceAllMapped(_output, (match) {
        final value = _read(match[1]!, profile);
        final fallback = match[2];
        return fallback != null && _isBlankForDefault(value)
            ? fallback.substring(1, fallback.length - 1)
            : _display(value);
      });

  static bool hasRequiredValues(
    List<String> paths,
    Map<String, Object?> profile,
  ) {
    final attributes = profile['attributes'];
    return paths.every((path) {
      final relative = path.startsWith('attributes.')
          ? path.substring('attributes.'.length)
          : path;
      Object? value = attributes;
      for (final key in relative.split('.')) {
        value = value is Map ? value[key] : null;
      }
      return _hasValue(value);
    });
  }

  static Object? _read(String path, Map<String, Object?> profile) {
    final root = path.startsWith('attributes') ? 'attributes' : 'profile';
    Object? value = root == 'attributes' ? profile['attributes'] : profile;
    for (final match in _segment.allMatches(path.substring(root.length))) {
      final position = match[2];
      if (position == null) {
        value = value is Map ? value[match[1] ?? match[3] ?? match[4]] : null;
      } else {
        final index = int.tryParse(position);
        value = value is List && index != null && index < value.length
            ? value[index]
            : null;
      }
    }
    return value;
  }

  static bool _isBlankForDefault(Object? value) =>
      value == null ||
      value == false ||
      value == '' ||
      (value is List && value.isEmpty);

  static String _display(Object? value) {
    if (value == null) return '';
    if (value is String || value is bool) return '$value';
    if (value is List) return value.map(_display).join();
    if (value is int) return '$value';
    if (value is double && value.isFinite) {
      return value == value.truncateToDouble()
          ? value.toStringAsFixed(0)
          : '$value';
    }
    return '';
  }

  static bool _hasValue(Object? value) {
    if (value == null) return false;
    if (value is List) return value.any(_hasValue);
    if (value is Map) return value.values.any(_hasValue);
    if (value is String) return value.trim().isNotEmpty;
    return true;
  }
}
