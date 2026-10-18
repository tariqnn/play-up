import 'package:flutter_test/flutter_test.dart';
import 'package:playup/map_links.dart';

void main() {
  test('Google Maps URL opens directions to venue coordinates', () {
    final uri = MapLinks.googleDirections(
      name: 'Infinity 3x3 Court',
      address: 'Amman, Jordan',
      latitude: 31.9648333,
      longitude: 35.8961111,
    );

    expect(uri?.host, 'www.google.com');
    expect(uri?.path, '/maps/dir/');
    expect(uri?.queryParameters['api'], '1');
    expect(
      uri?.queryParameters['destination'],
      '31.9648333,35.8961111',
    );
    expect(uri?.queryParameters['travelmode'], 'driving');
  });

  test('map links use the venue name and address when coordinates are absent', () {
    final google = MapLinks.googleDirections(
      name: 'Infinity Sports',
      address: 'Shmeisani, Amman',
    );
    final osm = MapLinks.openStreetMap(
      name: 'Infinity Sports',
      address: 'Shmeisani, Amman',
    );

    expect(
      google?.queryParameters['destination'],
      'Infinity Sports, Shmeisani, Amman',
    );
    expect(osm?.path, '/search');
    expect(osm?.queryParameters['query'], 'Infinity Sports, Shmeisani, Amman');
  });

  test('map links are unavailable when neither coordinates nor place exist', () {
    expect(MapLinks.googleDirections(name: '  '), isNull);
    expect(MapLinks.openStreetMap(name: '  '), isNull);
  });
}
