cmake_minimum_required(VERSION 3.18)
project(wenku_book_engine LANGUAGES C CXX)
set(CMAKE_SKIP_RPATH TRUE)

get_filename_component(WENKU_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../.." ABSOLUTE)
set(USE_ENCRYPTION OFF CACHE BOOL "" FORCE)
set(USE_LIBXML2 OFF CACHE BOOL "" FORCE)
set(USE_XMLWRITER ON CACHE BOOL "" FORCE)
set(USE_ZLIB ON CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
add_subdirectory("${WENKU_ROOT}/third_party/libmobi" "${CMAKE_CURRENT_BINARY_DIR}/libmobi" EXCLUDE_FROM_ALL)
# HAP libraries use unversioned names; retain a separately replaceable LGPL .so.
set_property(TARGET mobi PROPERTY VERSION)
set_property(TARGET mobi PROPERTY SOVERSION)

add_library(wenku_book_engine SHARED mobi_napi.cpp "${WENKU_ROOT}/android/app/src/main/cpp/mobi_export.c")
target_compile_features(wenku_book_engine PRIVATE cxx_std_17)
target_include_directories(wenku_book_engine PRIVATE "${WENKU_ROOT}/platforms/book_engine/include" "${WENKU_ROOT}/third_party/libmobi/src")
target_link_libraries(wenku_book_engine PRIVATE mobi libace_napi.z.so)
