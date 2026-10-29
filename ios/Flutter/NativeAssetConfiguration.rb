require 'json'
require 'open3'

# Flutter 3.41 installs native assets into one shared iOS output directory, while
# caching the installation separately for device/simulator build configurations.
# Refresh only installation manifests when that shared output has the other SDK.
# Flutter still builds, signs and installs the actual binaries itself.
module WenkuNativeAssetConfiguration
  def self.expected(sdk)
    return 'IOSSIMULATOR' if sdk.start_with?('iphonesimulator')
    return 'IOS' if sdk.start_with?('iphoneos')
    raise "Unsupported iOS SDK: #{sdk}"
  end

  def self.platforms(file)
    output, error, status = Open3.capture3('/usr/bin/xcrun', 'vtool', '-show-build', file)
    raise "Cannot inspect iOS native asset #{File.basename(file)}: #{error}" unless status.success?
    values = output.scan(/^\s*platform\s+(\S+)/).flatten.uniq
    raise "No platform in iOS native asset #{File.basename(file)}" if values.empty?
    values
  end

  def self.binaries(build)
    Dir.glob(File.join(build, 'native_assets', 'ios', '*.framework')).map do |folder|
      file = File.join(folder, File.basename(folder, '.framework'))
      file if File.file?(file)
    end.compact
  end

  def self.prepare(project, build, sdk, inspect: method(:platforms))
    target = expected(sdk)
    installed = binaries(build)
    return 0 if installed.empty? || installed.all? { |file| inspect.call(file) == [target] }

    inspected = {}
    count = 0
    Dir.glob(File.join(project, '.dart_tool', 'flutter_build', '*', 'dart_build_result.json')).each do |result|
      manifest = File.join(File.dirname(result), 'native_assets.json')
      next unless File.file?(manifest) && !File.symlink?(manifest)
      matching = JSON.parse(File.read(result)).fetch('code_assets', []).any? do |entry|
        encoding = entry.dig('asset', 'encoding') || {}
        file = encoding['file']
        entry.fetch('target', '').start_with?('ios_') &&
          encoding.dig('link_mode', 'type') == 'dynamic_loading_bundle' &&
          file.is_a?(String) && File.file?(file) &&
          (inspected[file] ||= inspect.call(file)) == [target]
      end
      next unless matching
      File.delete(manifest)
      count += 1
    end
    count
  end

  def self.verify(build, sdk, inspect: method(:platforms))
    target = expected(sdk)
    binaries(build).each do |file|
      raise "iOS native asset uses the wrong SDK: #{File.basename(file)}" unless inspect.call(file) == [target]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  project = File.expand_path(ENV['FLUTTER_APPLICATION_PATH'] || '..', ENV.fetch('SRCROOT'))
  build = File.expand_path(ENV.fetch('FLUTTER_BUILD_DIR', 'build'), project)
  sdk = ENV['PLATFORM_NAME'] || ENV.fetch('SDK_NAME')
  case ARGV.fetch(0)
  when 'prepare'
    count = WenkuNativeAssetConfiguration.prepare(project, build, sdk)
    puts "Refreshing #{count} iOS native-asset installation manifests after SDK change" if count > 0
  when 'verify'
    WenkuNativeAssetConfiguration.verify(build, sdk)
  else
    raise 'Expected prepare or verify'
  end
end
