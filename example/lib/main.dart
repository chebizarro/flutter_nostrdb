import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_nostrdb/flutter_nostrdb.dart';
import 'package:path_provider/path_provider.dart';

// Entry point
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initDatabaseFile();
  final dir = await getApplicationDocumentsDirectory();
  runApp(NostrDbEditorApp(dir: dir.path));
}

// Copy data.mdb from assets to local directory
Future<void> _initDatabaseFile() async {
  final bytes = await rootBundle.load('assets/data.mdb');
  final dir = await getApplicationDocumentsDirectory();
  final dbPath = '${dir.path}/data.mdb';
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
  State<NostrDbHomePage> createState() => _NostrDbHomePageState();
}

class _NostrDbHomePageState extends State<NostrDbHomePage> {
  late String _dbPath;
  bool _isDbOpen = false;

  // For showing stats
  String _statsText = '';

  // Filter inputs:
  final TextEditingController _kindsController = TextEditingController();
  final TextEditingController _authorsController = TextEditingController();
  final TextEditingController _sinceController = TextEditingController();
  final TextEditingController _untilController = TextEditingController();
  final TextEditingController _limitController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  String _filterResults = 'No query run yet.';
  List<Map<String, dynamic>> _queryResults = [];

  @override
  void initState() {
    super.initState();
    _dbPath = widget.dir; // default to user's documents directory
  }

  @override
  void dispose() {
    if (_isDbOpen && NostrDb.instance != null) {
      NostrDb.instance!.closeDb();
    }
    super.dispose();
  }

  /// Let user type in new DB path
  Future<void> _pickDbPath() async {
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

  /// Open DB
  void _openDb() {
    final result = NostrDb.openDb(
      _dbPath,
      flags: 0,
      threads: 2,
      scratchSize: 2 * 1024 * 1024,
      mapsizeMB: 1024,
    );
    setState(() {
      _isDbOpen = result;
      _statsText = '';
    });
  }

  /// Close DB
  void _closeDb() {
    if (!_isDbOpen) return;
    NostrDb.instance?.closeDb();
    setState(() {
      _isDbOpen = false;
      _statsText = '';
      _queryResults.clear();
    });
  }

  /// Get stats
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
    final buffer = StringBuffer();
    buffer.writeln('DBS (16 total):');
    for (int i = 0; i < 16; i++) {
      final counts = st.dbs[i];
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

  /// Build a filter from the UI text fields
  Map<String, dynamic> _buildFilterDict() {
    final Map<String, dynamic> filter = {};

    // kinds -> parse comma-separated numbers
    if (_kindsController.text.trim().isNotEmpty) {
      final kindsList =
          _kindsController.text
              .split(',')
              .map((e) => int.tryParse(e.trim()))
              .whereType<int>()
              .toList();
      if (kindsList.isNotEmpty) filter['kinds'] = kindsList;
    }

    // authors -> parse comma-separated hex strings or pubkeys
    if (_authorsController.text.trim().isNotEmpty) {
      final authors =
          _authorsController.text
              .split(',')
              .map((e) => e.trim())
              .where((s) => s.isNotEmpty)
              .toList();
      if (authors.isNotEmpty) filter['a'] = authors;
    }

    // since -> parse int
    if (_sinceController.text.trim().isNotEmpty) {
      final val = int.tryParse(_sinceController.text.trim());
      if (val != null) filter['since'] = val;
    }

    // until -> parse int
    if (_untilController.text.trim().isNotEmpty) {
      final val = int.tryParse(_untilController.text.trim());
      if (val != null) filter['until'] = val;
    }

    // limit -> parse int
    if (_limitController.text.trim().isNotEmpty) {
      final val = int.tryParse(_limitController.text.trim());
      if (val != null) filter['limit'] = val;
    }

    // search -> string
    if (_searchController.text.trim().isNotEmpty) {
      final val = _searchController.text.trim();
      if (val.isNotEmpty) filter['search'] = val;
    }

    return filter;
  }

  /// Run the filter
  void _runFilter() {
    final api = NostrDb.instance;
    if (api == null) {
      setState(() {
        _filterResults = 'DB not open.';
      });
      return;
    }

    final filterDict = _buildFilterDict();
    // Suppose you have a bridging function: NostrDb.instance!.query(filterMap)
    // that returns a list of results (maps or objects).
    final results = api.query(
      filterDict,
    ); // a list of maps, e.g. [{'id': '...', 'content': '...'}, ...]

    setState(() {
      _filterResults = 'Filter: $filterDict';
      _queryResults = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dbStatus =
        _isDbOpen ? 'DB is open (result=$_isDbOpen)' : 'DB is closed.';
    return Scaffold(
      appBar: AppBar(title: const Text('NostrDB Editor with Filter UI')),
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

              // Filter UI
              const Text(
                'Filters',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _kindsController,
                decoration: const InputDecoration(
                  labelText: 'Kinds (comma-separated)',
                  hintText: 'e.g. 0, 1, 2',
                ),
              ),
              TextField(
                controller: _authorsController,
                decoration: const InputDecoration(
                  labelText: 'Authors (comma-separated hex/pubkeys)',
                ),
              ),
              TextField(
                controller: _sinceController,
                decoration: const InputDecoration(
                  labelText: 'Since (unix time)',
                ),
                keyboardType: TextInputType.datetime,
              ),
              TextField(
                controller: _untilController,
                decoration: const InputDecoration(
                  labelText: 'Until (unix time)',
                ),
                keyboardType: TextInputType.datetime,
              ),
              TextField(
                controller: _limitController,
                decoration: const InputDecoration(
                  labelText: 'Limit (int)',
                  hintText: 'e.g. 100',
                ),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search (string)',
                  hintText: 'e.g. GM!',
                ),
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _isDbOpen ? _runFilter : null,
                child: const Text('Run Filter'),
              ),

              const SizedBox(height: 8),
              Text(
                _filterResults,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 8),

              // Show query results:
              if (_queryResults.isNotEmpty) ...[
                const Text(
                  'Results:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _queryResults.length,
                    itemBuilder: (ctx, i) {
                      final item = _queryResults[i];
                      // Suppose item has 'id' and 'content'
                      return ListTile(
                        title: Text('${item['id']}'),
                        subtitle: Text('${item['content'] ?? ''}'),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
