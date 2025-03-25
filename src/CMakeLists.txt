# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(flutter_nostrdb_library VERSION 0.0.1 LANGUAGES C)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wno-misleading-indentation -Wno-unused-function \
    -Werror -O2 -g -fPIC -DCCAN_TAL_NEVER_RETURN_NULL=1")

# On macOS, you may need to link Security framework (adjust as needed):
if(APPLE)
  set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -framework Security")
endif()

# ---------------------------------------------------------------------------
# Include directories
# ---------------------------------------------------------------------------
include_directories(
  ${CMAKE_CURRENT_SOURCE_DIR}/nostrdb/src
  ${CMAKE_CURRENT_SOURCE_DIR}/nostrdb/deps/secp256k1/include
  ${CMAKE_CURRENT_SOURCE_DIR}/nostrdb/deps/lmdb
  ${CMAKE_CURRENT_SOURCE_DIR}/nostrdb/deps/flatcc/include
  ${CMAKE_CURRENT_SOURCE_DIR}/nostrdb/src/bolt11
  ${CMAKE_CURRENT_SOURCE_DIR}/nostrdb/ccan
)

# ---------------------------------------------------------------------------
# Source lists
# ---------------------------------------------------------------------------
# 1) Primary nostrdb sources
set(NOSTRDB_SRC
  nostrdb/src/nostrdb.c
  nostrdb/src/invoice.c
  nostrdb/src/nostr_bech32.c
  nostrdb/src/content_parser.c
  nostrdb/src/block.c
)

# 2) BOLT11 sources
set(BOLT11_SRC
  nostrdb/src/bolt11/bolt11.c
  nostrdb/src/bolt11/bech32.c
  nostrdb/src/bolt11/amount.c
  nostrdb/src/bolt11/hash_u5.c
)

# 3) FlatCC runtime
set(FLATCC_SRC
  nostrdb/deps/flatcc/src/runtime/json_parser.c
  nostrdb/deps/flatcc/src/runtime/verifier.c
  nostrdb/deps/flatcc/src/runtime/builder.c
  nostrdb/deps/flatcc/src/runtime/emitter.c
  nostrdb/deps/flatcc/src/runtime/refmap.c
)

# 4) CCAN sources
set(CCAN_SRC
  nostrdb/ccan/ccan/utf8/utf8.c
  nostrdb/ccan/ccan/tal/tal.c
  nostrdb/ccan/ccan/tal/str/str.c
  nostrdb/ccan/ccan/list/list.c
  nostrdb/ccan/ccan/mem/mem.c
  nostrdb/ccan/ccan/crypto/sha256/sha256.c
  nostrdb/ccan/ccan/take/take.c
)

# 5) LMDB sources
set(LMDB_SRC
  nostrdb/deps/lmdb/mdb.c
  nostrdb/deps/lmdb/midl.c
)

# Combine all, but exclude secp256k1 from here,
# since we let secp256k1's own CMake build it.
set(ALL_SOURCES
  ${NOSTRDB_SRC}
  ${BOLT11_SRC}
  ${FLATCC_SRC}
  ${CCAN_SRC}
  ${LMDB_SRC}
)

# ---------------------------------------------------------------------------
# 2. Add subdirectory for secp256k1
# ---------------------------------------------------------------------------
# `nostrdb/deps/secp256k1` has its own CMakeLists that produces
# a target named `secp256k1` or `libsecp256k1` or similar.
#
# If building a shared library for Android, you may want to set:
#   -DSECP256K1_EXPERIMENTAL=ON
#   -DSECP256K1_ENABLE_MODULE_ECDH=ON
#   ...
# via -D variables, or use set(... CACHE ... FORCE).
#
# We'll rely on the default (BUILD_SHARED_LIBS=ON => produce a shared lib).
#
add_subdirectory(
  ${CMAKE_CURRENT_SOURCE_DIR}/nostrdb/deps/secp256k1
)

# ---------------------------------------------------------------------------
# 3. Create the flutter_nostrdb shared library
# ---------------------------------------------------------------------------
add_library(flutter_nostrdb SHARED
  ${ALL_SOURCES}
)

set_target_properties(flutter_nostrdb PROPERTIES
  PUBLIC_HEADER nostrdb/src/nostrdb.h
  OUTPUT_NAME "flutter_nostrdb"
)

target_compile_definitions(flutter_nostrdb PUBLIC DART_SHARED_LIB)

# Link the newly built secp256k1 library target
target_link_libraries(flutter_nostrdb
  PRIVATE
  secp256k1
)

# Android-specific fixes
if(ANDROID)
  # Avoid -Wmacro-redefined -> error
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-error=macro-redefined")
  # Fix max page size
  target_link_options(flutter_nostrdb PRIVATE "-Wl,-z,max-page-size=16384")
endif()

message(STATUS "Building flutter_nostrdb with an external subproject for secp256k1.")
