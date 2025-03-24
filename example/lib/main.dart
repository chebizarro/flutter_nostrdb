import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'package:flutter_nostrdb/flutter_nostrdb.dart' as flutter_nostrdb;
import 'package:path_provider/path_provider.dart';

import 'dart:ffi';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initDatabaseFile();
  final dir = await getApplicationDocumentsDirectory();
  runApp(MyApp(dir: dir.path));
}

Future<void> _initDatabaseFile() async {
  // 1. Load the asset
  final bytes = await rootBundle.load('assets/data.mdb');

  // 2. Determine a writable location. For example, app's documents dir.
  final dir = await getApplicationDocumentsDirectory();
  final dbPath = '${dir.path}/data.mdb';

  // 3. Write the bytes to a file on the device
  final file = File(dbPath);
  if (!file.existsSync()) {
    await file.writeAsBytes(bytes.buffer.asUint8List());
    debugPrint('Copied data.mdb to $dbPath');
  } else {
    debugPrint('data.mdb already exists at $dbPath');
  }
}

class MyApp extends StatefulWidget {
  final String dir;
  const MyApp({super.key, required this.dir});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late int sumResult;
  late Future<int> sumAsyncResult;
  late flutter_nostrdb.NostrDb nostrDb;

  @override
  void initState() {
    super.initState();
    final dbConfig = flutter_nostrdb.NostrDbConfig();

    nostrDb = flutter_nostrdb.NostrDb(widget.dir, dbConfig);
    final stats = flutter_nostrdb.NostrDbStat(nostrDb);
    sumResult = stats.dbs[0].key_size;
    sumAsyncResult = Future(() => 0);
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 25);
    const spacerSmall = SizedBox(height: 10);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Native Packages')),
        body: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                const Text(
                  'This calls a native function through FFI that is shipped as source in the package. '
                  'The native code is built as part of the Flutter Runner build.',
                  style: textStyle,
                  textAlign: TextAlign.center,
                ),
                spacerSmall,
                Text(
                  'sum(1, 2) = $sumResult',
                  style: textStyle,
                  textAlign: TextAlign.center,
                ),
                spacerSmall,
                FutureBuilder<int>(
                  future: sumAsyncResult,
                  builder: (BuildContext context, AsyncSnapshot<int> value) {
                    final displayValue =
                        (value.hasData) ? value.data : 'loading';
                    return Text(
                      'await sumAsync(3, 4) = $displayValue',
                      style: textStyle,
                      textAlign: TextAlign.center,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
