import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final output = File('artifacts/app-store/$name.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes, flush: true);
      return true;
    },
    writeResponseOnFailure: true,
  );
}
