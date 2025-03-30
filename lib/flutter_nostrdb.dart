import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart' as ffi;
import 'package:convert/convert.dart';

import 'flutter_nostrdb_bindings_generated.dart';

class NostrDb {
  final Pointer<Ndb> _ndbPtr;

  NostrDb._(this._ndbPtr);

  static NostrDb? _instance;
  static NostrDb? get instance => _instance;

  /// Creates or re-initializes the DB
  static bool openDb(
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
    return (result == 1);
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
        ndb_filter_fieldtype.NDB_FILTER_UNTIL,
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
      final search = filter['search'] as String;
      final searchPtr = search.toNativeUtf8();
      _bindings.ndb_filter_add_str_element(filterPtr, searchPtr.cast());
      _bindings.ndb_filter_end_field(filterPtr);
      ffi.calloc.free(searchPtr);
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

  bool processEvent(String event) {
    final eventPtr = event.toNativeUtf8();
    final result = _bindings.ndb_process_event(
      _ndbPtr,
      eventPtr.cast(),
      event.length,
    );
    ffi.calloc.free(eventPtr);
    return (result == 1);
  }

  /// gets the raw profile data for a pubkey
  String? getProfile(String pubkey) {
    final bytes = hex.decode(pubkey);
    final pkPtr = ffi.calloc<Uint8>(bytes.length);
    final profileLen = ffi.calloc<Size>();
    final txn = ffi.calloc<ndb_txn>();
    final key = ffi.calloc<Uint64>();

    _bindings.ndb_begin_query(_ndbPtr, txn);

    final ptr = _bindings.ndb_get_profile_by_pubkey(
      txn,
      pkPtr.cast(),
      profileLen,
      key,
    );

    _bindings.ndb_end_query(txn);

    final Uint8List byteList = ptr.cast<Uint8>().asTypedList(5000000);
    final meaningfulBytes = byteList.sublist(0, profileLen.value);
    final profile = utf8.decode(meaningfulBytes);

    ffi.calloc.free(pkPtr);
    ffi.calloc.free(profileLen);
    ffi.calloc.free(txn);
    ffi.calloc.free(key);
    ffi.calloc.free(ptr);

    return profile;
  }
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
