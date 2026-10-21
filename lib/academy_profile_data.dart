/// Normalizes legacy scalar and current array values from academy documents.
///
/// Production records have used both a string and a list for fields such as
/// `sports` and `trainingPackages`; editors should accept either.
List<dynamic> academyFieldList(Object? value) {
  if (value is List) return value;
  if (value is String && value.trim().isNotEmpty) return [value.trim()];
  return const [];
}

/// Normalizes academy package records that have existed as maps or names.
/// Unexpected legacy values are ignored instead of crashing profile rendering.
List<Map<String, dynamic>> academyPackageList(
  Object? packages, {
  Object? legacyNames,
}) {
  final result = <Map<String, dynamic>>[];
  for (final item in academyFieldList(packages)) {
    if (item is Map) {
      final row = <String, dynamic>{
        for (final entry in item.entries)
          if (entry.key != null) entry.key.toString(): entry.value,
      };
      final title = row['title']?.toString().trim() ?? '';
      if (title.isNotEmpty) {
        row['title'] = title;
        result.add(row);
      }
    } else if (item is String && item.trim().isNotEmpty) {
      result.add({'title': item.trim()});
    }
  }

  for (final item in academyFieldList(legacyNames)) {
    if (item is! String || item.trim().isEmpty) continue;
    final title = item.trim();
    if (!result.any((row) => row['title']?.toString() == title)) {
      result.add({'title': title});
    }
  }
  return result;
}

/// Reads academy photo URLs without assuming every stored entry is valid.
List<String> academyImageList(Object? value) => academyFieldList(value)
    .whereType<String>()
    .map((url) => url.trim())
    .where((url) => url.isNotEmpty)
    .toList(growable: false);
