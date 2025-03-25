import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart' as ffi;
import 'package:convert/convert.dart';

import 'flutter_nostrdb_bindings_generated.dart';

class NostrDb {
  /// The pointer to `struct ndb*`.
  final Pointer<Ndb> _ndbPtr;

  NostrDb._(this._ndbPtr);

  static NostrDb? _instance;
  static NostrDb? get instance => _instance;

  /// Creates or re-initializes the DB
  static int openDb(
    String dbPath, {
    int flags = 0,
    int threads = 2,
    int scratchSize = 2 * 1024 * 1024,
    int mapsizeMB = 1024,
  }) {
    final configPtr = ffi.calloc<NdbConfig>();
    configPtr.ref
      ..flags = flags
      ..ingester_threads = threads
      ..writer_scratch_buffer_size = scratchSize
      ..mapsize = (mapsizeMB * 1024 * 1024);

    final dbPtrPtr = ffi.calloc<Pointer<Ndb>>();
    final pathUtf8 = dbPath.toNativeUtf8();

    final result = _bindings.ndb_init(dbPtrPtr, pathUtf8.cast(), configPtr);

    if (result == 1) {
      // success
      final ndbPtr = dbPtrPtr.value;
      _instance = NostrDb._(ndbPtr);
    }

    ffi.calloc.free(pathUtf8);
    ffi.calloc.free(dbPtrPtr);
    ffi.calloc.free(configPtr);
    return result;
  }

  /// Closes DB
  void closeDb() {
    _bindings.ndb_destroy(_ndbPtr);
  }

  /// Get DB stats
  NdbStat? getStats() {
    final statPtr = ffi.calloc<NdbStat>();
    final r = _bindings.ndb_stat(_ndbPtr, statPtr);
    if (r == 1) {
      // success
      final statVal = statPtr.ref;
      ffi.calloc.free(statPtr);
      return statVal;
    }
    ffi.calloc.free(statPtr);
    return null;
  }

  List<Map<String, dynamic>> query(Map<String, dynamic> filter) {
    final List<Map<String, dynamic>> results = [];
    final filterPtr = ffi.calloc<ndb_filter>();
    _bindings.ndb_filter_init(filterPtr);

    if (filter.containsKey('kinds')) {
      _bindings.ndb_filter_start_field(
        filterPtr,
        ndb_filter_fieldtype.NDB_FILTER_KINDS,
      );
      filter['kinds'].forEach((kind) {
        _bindings.ndb_filter_add_int_element(filterPtr, kind);
      });
      _bindings.ndb_filter_end_field(filterPtr);
    }

    if (filter.containsKey('limit')) {
      _bindings.ndb_filter_start_field(
        filterPtr,
        ndb_filter_fieldtype.NDB_FILTER_LIMIT,
      );
      final limit = filter['limit'];
      _bindings.ndb_filter_add_int_element(filterPtr, limit);
      _bindings.ndb_filter_end_field(filterPtr);
    }

    if (filter.containsKey('since')) {
      _bindings.ndb_filter_start_field(
        filterPtr,
        ndb_filter_fieldtype.NDB_FILTER_SINCE,
      );
      final since = filter['since'];
      _bindings.ndb_filter_add_int_element(filterPtr, since);
      _bindings.ndb_filter_end_field(filterPtr);
    }

    if (filter.containsKey('until')) {
      _bindings.ndb_filter_start_field(
        filterPtr,
        ndb_filter_fieldtype.NDB_FILTER_SINCE,
      );
      final until = filter['until'];
      _bindings.ndb_filter_add_int_element(filterPtr, until);
      _bindings.ndb_filter_end_field(filterPtr);
    }

    if (filter.containsKey('t')) {
      _bindings.ndb_filter_start_tag_field(filterPtr, 't'.codeUnitAt(0));
      final tag = filter['t'];
      _bindings.ndb_filter_add_str_element(filterPtr, tag);
      _bindings.ndb_filter_end_field(filterPtr);
    }

    if (filter.containsKey('search')) {
      _bindings.ndb_filter_start_field(
        filterPtr,
        ndb_filter_fieldtype.NDB_FILTER_SEARCH,
      );
      final search = filter['search'];
      _bindings.ndb_filter_add_str_element(filterPtr, search);
      _bindings.ndb_filter_end_field(filterPtr);
    }

    if (filter.containsKey('e')) {
      _bindings.ndb_filter_start_tag_field(filterPtr, 'e'.codeUnitAt(0));
      filter['e'].forEach((tag) {
        final bytes = hex.decode(tag);
        final ptr = ffi.calloc<Uint8>(bytes.length);
        final byteList = ptr.asTypedList(bytes.length);
        byteList.setAll(0, bytes);
        _bindings.ndb_filter_add_id_element(filterPtr, ptr.cast());
        ffi.calloc.free(ptr);
      });
      _bindings.ndb_filter_end_field(filterPtr);
    }

    if (filter.containsKey('a')) {
      _bindings.ndb_filter_start_field(
        filterPtr,
        ndb_filter_fieldtype.NDB_FILTER_AUTHORS,
      );
      final tag = filter['a'];
      final bytes = hex.decode(tag);
      final ptr = ffi.calloc<Uint8>(bytes.length);
      final byteList = ptr.asTypedList(bytes.length);
      byteList.setAll(0, bytes);
      _bindings.ndb_filter_add_id_element(filterPtr, ptr.cast());
      ffi.calloc.free(ptr);
      _bindings.ndb_filter_end_field(filterPtr);
    }

    final ndbQueryResultPtr = ffi.calloc<ndb_query_result>(1000);
    final txn = ffi.calloc<ndb_txn>();
    final count = ffi.calloc<Int>();

    _bindings.ndb_begin_query(_ndbPtr, txn);
    final querySuccess = _bindings.ndb_query(
      txn,
      filterPtr,
      1,
      ndbQueryResultPtr,
      1000,
      count,
    );
    _bindings.ndb_end_query(txn);

    if (querySuccess == 1) {
      // example usage:
      final actualCount = count.value;
      for (int i = 0; i < actualCount; i++) {
        final result = ndbQueryResultPtr[i].note;
        final buffer = ffi.calloc<Char>(5000000);
        _bindings.ndb_note_json(result, buffer, 5000000);
        final Uint8List byteList = buffer.cast<Uint8>().asTypedList(5000000);
        int actualLength = 0;
        while (actualLength < 5000000 && byteList[actualLength] != 0) {
          actualLength++;
        }
        final meaningfulBytes = byteList.sublist(0, actualLength);
        final message = utf8.decode(meaningfulBytes);
        final event = jsonDecode(message);
        results.add(event);
        ffi.calloc.free(buffer);
      }
    }

    ffi.calloc.free(ndbQueryResultPtr);
    ffi.calloc.free(txn);
    ffi.calloc.free(count);
    ffi.calloc.free(filterPtr);
    return results;
  }
}

/// A longer lived native function, which occupies the thread calling it.
///
/// Do not call these kind of native functions in the main isolate. They will
/// block Dart execution. This will cause dropped frames in Flutter applications.
/// Instead, call these native functions on a separate isolate.
///
/// Modify this to suit your own use case. Example use cases:
///
/// 1. Reuse a single isolate for various different kinds of requests.
/// 2. Use multiple helper isolates for parallel execution.
Future<int> sumAsync(int a, int b) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextSumRequestId++;
  final _SumRequest request = _SumRequest(requestId, a, b);
  final Completer<int> completer = Completer<int>();
  _sumRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

const String _libName = 'flutter_nostrdb';

/// The dynamic library in which the symbols for [FlutterNostrdbBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final FlutterNostrdbBindings _bindings = FlutterNostrdbBindings(_dylib);

/// A request to compute `sum`.
///
/// Typically sent from one isolate to another.
class _SumRequest {
  final int id;
  final int a;
  final int b;

  const _SumRequest(this.id, this.a, this.b);
}

/// A response with the result of `sum`.
///
/// Typically sent from one isolate to another.
class _SumResponse {
  final int id;
  final int result;

  const _SumResponse(this.id, this.result);
}

/// Counter to identify [_SumRequest]s and [_SumResponse]s.
int _nextSumRequestId = 0;

/// Mapping from [_SumRequest] `id`s to the completers corresponding to the correct future of the pending request.
final Map<int, Completer<int>> _sumRequests = <int, Completer<int>>{};

/// The SendPort belonging to the helper isolate.
Future<SendPort> _helperIsolateSendPort = () async {
  // The helper isolate is going to send us back a SendPort, which we want to
  // wait for.
  final Completer<SendPort> completer = Completer<SendPort>();

  // Receive port on the main isolate to receive messages from the helper.
  // We receive two types of messages:
  // 1. A port to send messages on.
  // 2. Responses to requests we sent.
  final ReceivePort receivePort =
      ReceivePort()..listen((dynamic data) {
        if (data is SendPort) {
          // The helper isolate sent us the port on which we can sent it requests.
          completer.complete(data);
          return;
        }
        if (data is _SumResponse) {
          // The helper isolate sent us a response to a request we sent.
          final Completer<int> completer = _sumRequests[data.id]!;
          _sumRequests.remove(data.id);
          completer.complete(data.result);
          return;
        }
        throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
      });

  // Start the helper isolate.
  await Isolate.spawn((SendPort sendPort) async {
    final ReceivePort helperReceivePort =
        ReceivePort()..listen((dynamic data) {
          // On the helper isolate listen to requests and respond to them.
          if (data is _SumRequest) {
            //final int result = _bindings.sum_long_running(data.a, data.b);
            //final _SumResponse response = _SumResponse(data.id, result);
            //sendPort.send(response);
            return;
          }
          throw UnsupportedError(
            'Unsupported message type: ${data.runtimeType}',
          );
        });

    // Send the port to the main isolate on which we can receive requests.
    sendPort.send(helperReceivePort.sendPort);
  }, receivePort.sendPort);

  // Wait until the helper isolate has sent us back the SendPort on which we
  // can start sending requests.
  return completer.future;
}();
