/// Builds external map destinations for venues.
abstract final class MapLinks {
  static String? destination({
    required String name,
    String address = '',
    double? latitude,
    double? longitude,
  }) {
    if (latitude != null && longitude != null) {
      return '$latitude,$longitude';
    }

    final place = [name.trim(), address.trim()]
        .where((part) => part.isNotEmpty)
        .join(', ');
    return place.isEmpty ? null : place;
  }

  static Uri? googleDirections({
    required String name,
    String address = '',
    double? latitude,
    double? longitude,
  }) {
    final place = destination(
      name: name,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
    if (place == null) return null;

    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': place,
      'travelmode': 'driving',
    });
  }

  static Uri? openStreetMap({
    required String name,
    String address = '',
    double? latitude,
    double? longitude,
  }) {
    if (latitude != null && longitude != null) {
      return Uri.https('www.openstreetmap.org', '/', {
        'mlat': '$latitude',
        'mlon': '$longitude',
      });
    }

    final place = destination(name: name, address: address);
    if (place == null) return null;
    return Uri.https('www.openstreetmap.org', '/search', {'query': place});
  }
}
