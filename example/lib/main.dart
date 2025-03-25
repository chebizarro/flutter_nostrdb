import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_nostrdb/flutter_nostrdb.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initDatabaseFile();
  final dir = await getApplicationDocumentsDirectory();
  runApp(NostrDbEditorApp(dir: dir.path));
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

class NostrDbEditorApp extends StatelessWidget {
  final String dir;
  const NostrDbEditorApp({super.key, required this.dir});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NostrDB Editor',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: NostrDbHomePage(dir: dir),
    );
  }
}

class NostrDbHomePage extends StatefulWidget {
  final String dir;
  const NostrDbHomePage({super.key, required this.dir});

  @override
  State<NostrDbHomePage> createState() => _NostrDbHomePageState(dir);
}

class _NostrDbHomePageState extends State<NostrDbHomePage> {
  String _dbPath;
  int _openResult = -1;
  bool _isDbOpen = false;

  // For showing stats
  String _statsText = '';

  // For queries (super simplified)
  final _queryController = TextEditingController();
  String _queryResults = 'No query run yet.';

  _NostrDbHomePageState(this._dbPath);

  @override
  void dispose() {
    if (_isDbOpen && NostrDb.instance != null) {
      NostrDb.instance!.closeDb();
    }
    super.dispose();
  }

  Future<void> _pickDbPath() async {
    // In a real app, you might use a file picker or similar approach.
    // For demonstration, let's do something like:
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: _dbPath);
        return AlertDialog(
          title: const Text('Enter DB directory path'),
          content: TextField(controller: ctrl),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (text == null) return;
    setState(() {
      _dbPath = text;
    });
  }

  void _openDb() {
    // For demonstration, pass default flags or config
    final result = NostrDb.openDb(
      _dbPath,
      flags: 0,
      threads: 2,
      scratchSize: 2 * 1024 * 1024,
      mapsizeMB: 1024,
    );
    setState(() {
      _openResult = result;
      _isDbOpen = (result == 1);
      _statsText = '';
    });
  }

  void _closeDb() {
    if (!_isDbOpen) return;
    NostrDb.instance?.closeDb();
    setState(() {
      _isDbOpen = false;
      _statsText = '';
      _openResult = -1;
    });
  }

  void _fetchStats() {
    final api = NostrDb.instance;
    if (api == null) return;
    final st = api.getStats();
    if (st == null) {
      setState(() {
        _statsText = 'Failed to get stats.';
      });
      return;
    }

    // st.dbs is an Array<ndb_stat_counts>, length=16
    final buffer = StringBuffer();
    buffer.writeln('DBS (16 total):');
    for (int i = 0; i < 16; i++) {
      final counts = st.dbs[i];
      // or use extension for [] if you have it
      buffer.writeln(
        'Index $i => count=${counts.count}, key_size=${counts.key_size}, val_size=${counts.value_size}',
      );
    }
    buffer.writeln('\nCommon Kinds (15 total):');
    for (int i = 0; i < 15; i++) {
      final ck = st.common_kinds[i];
      if (ck.count > 0) {
        buffer.writeln(
          'CKind $i => count=${ck.count}, key_size=${ck.key_size}, val_size=${ck.value_size}',
        );
      }
    }
    final other = st.other_kinds;
    if (other.count > 0) {
      buffer.writeln(
        '\nOther => count=${other.count}, key_size=${other.key_size}, val_size=${other.value_size}',
      );
    }

    setState(() {
      _statsText = buffer.toString();
    });
  }

  // Very simplified approach: we won't implement real ndb_query bridging
  // but let's pretend we do a note search or something
  void _runQuery() {
    final queryText = _queryController.text.trim();
    final api = NostrDb.instance;
    if (api == null) {
      setState(() {
        _queryResults = 'DB not open.';
      });
      return;
    }
    final results = NostrDb.instance!.query({
      'kinds': [1],
    });
    setState(() {
      _queryResults = results
          .map((e) => "${e['id']}:${e['content']}")
          .join('\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    final dbStatus =
        _isDbOpen ? 'DB is open (result=$_openResult)' : 'DB is closed.';
    return Scaffold(
      appBar: AppBar(title: const Text('NostrDB Editor')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dbStatus, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text('Current DB Path: $_dbPath')),
                  IconButton(
                    icon: const Icon(Icons.folder),
                    onPressed: _pickDbPath,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _openDb,
                    child: const Text('Open DB'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isDbOpen ? _closeDb : null,
                    child: const Text('Close DB'),
                  ),
                ],
              ),
              const Divider(),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _isDbOpen ? _fetchStats : null,
                    child: const Text('Get Stats'),
                  ),
                ],
              ),
              if (_statsText.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[200],
                  child: Text(_statsText),
                ),
              const Divider(),
              const Text('Query / Search:'),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. --kind 1 or something...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isDbOpen ? _runQuery : null,
                    child: const Text('Run'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _queryResults,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
