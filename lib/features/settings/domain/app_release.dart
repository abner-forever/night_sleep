String formatAppVersion(String version) {
  final value = version.split('+').first.replaceFirst(RegExp(r'^v'), '');
  final match =
      RegExp(r'^(.*)-(preview|beta|rc)\.([1-9]\d*)$').firstMatch(value);
  if (match == null) return value;
  final channel = switch (match[2]) {
    'preview' => 'Preview',
    'beta' => 'Beta',
    _ => 'RC',
  };
  return '${match[1]}（$channel ${match[3]}）';
}

class AppVersion implements Comparable<AppVersion> {
  AppVersion._(this.parts);

  final List<int> parts;

  static AppVersion? parse(String value) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:-(preview|beta|rc)\.([1-9]\d*))?$',
    ).firstMatch(value);
    if (match == null) return null;
    return AppVersion._([
      for (final index in [1, 2, 3]) int.parse(match[index]!),
      switch (match[4]) { 'preview' => 0, 'beta' => 1, 'rc' => 2, _ => 3 },
      int.parse(match[5] ?? '0'),
    ]);
  }

  bool get isPrerelease => parts[3] < 3;

  @override
  int compareTo(AppVersion other) {
    for (var index = 0; index < parts.length; index++) {
      final comparison = parts[index].compareTo(other.parts[index]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }
}

class AppRelease {
  const AppRelease({
    required this.version,
    required this.buildNumber,
    required this.url,
    required this.sha256,
    required this.size,
    required this.notes,
  });

  final String version;
  final int buildNumber;
  final Uri url;
  final String sha256;
  final int size;
  final String notes;
}
