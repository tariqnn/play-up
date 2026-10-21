/// Normalizes legacy scalar and current array values from academy documents.
///
/// Production records have used both a string and a list for fields such as
/// `sports` and `trainingPackages`; editors should accept either.
List<dynamic> academyFieldList(Object? value) {
  if (value is List) return value;
  if (value is String && value.trim().isNotEmpty) return [value.trim()];
  return const [];
}
