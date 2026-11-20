import 'package:flutter/widgets.dart';
import 'package:tremulator/src/lab_call.dart';
import 'package:tremulator/src/lab_host.dart';

/// `--lab ...` runs one measured call (see [LabOptions]); anything else
/// shows the placeholder until the screens exist. In a browser the
/// arguments come from the page's address (`?lab=&name=bob...`).
void main(List<String> argv) {
  WidgetsFlutterBinding.ensureInitialized();
  final args = labArguments(argv);
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
