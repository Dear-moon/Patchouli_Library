Pod::Spec.new do |s|
  s.name = 'WenkuBookEngine'
  s.version = '0.1.0'
  s.summary = 'Local, unencrypted Kindle import for the Flutter reader.'
  s.homepage = 'https://github.com/mikufoxxx/Wenku8_Flutter'
  s.license = { :type => 'LGPL-3.0-or-later', :file => 'third_party/libmobi/COPYING' }
  s.author = 'Wenku8 contributors; libmobi by Bartek Fabiszewski'
  s.source = { :path => '.' }
  s.platform = :ios, '13.0'
  s.source_files = 'platforms/book_engine/include/WenkuBookEngine.h',
    'android/app/src/main/cpp/mobi_export.c',
    'third_party/libmobi/src/{buffer,compression,debug,index,memory,meta,opf,parse_rawml,read,structure,util,write,xmlwriter}.{c,h}',
    'third_party/libmobi/src/{config,mobi}.h'
  s.public_header_files = 'platforms/book_engine/include/WenkuBookEngine.h'
  s.libraries = 'z'
  s.pod_target_xcconfig = {
    'GCC_C_LANGUAGE_STANDARD' => 'c99',
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/third_party/libmobi/src"',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) PACKAGE_VERSION=\"0.12\" USE_XMLWRITER HAVE_UNISTD_H HAVE_STRDUP HAVE_SYS_RESOURCE_H HAVE_ATTRIBUTE_NORETURN MOBI_INLINE=inline',
    'DEFINES_MODULE' => 'YES'
  }
  # Dynamic linking retains a replaceable LGPL library. No JNI, desktop tools,
  # DRM/encryption sources, downloaded binaries or bundled book samples.
  s.static_framework = false
end
