import 'package:flutter/widgets.dart';
import 'package:tremulator/src/lab_call.dart';

/// `--lab ...` runs one measured call (see [LabOptions]); anything else
/// shows the placeholder until the screens exist.
void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains('--lab')) {
    runApp(LabCallApp(LabOptions.parse(args)));
  } else {
    runApp(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: Text('tremulator: no screens yet')),
      ),
    );
  }
}
