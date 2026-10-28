require 'fileutils'
require 'json'

# Use Flutter's generated registry as the source of truth. Test pods and their
# registrations belong to Debug, without editing the SDK or its generated files.
module WenkuPluginConfiguration
  def self.development(metadata)
    metadata.fetch('plugins', {}).fetch('ios', []).select do |plugin|
      plugin['dev_dependency'] && plugin.fetch('native_build', true)
    end
  end

  def self.registry(source, metadata, configuration)
    return source if configuration.start_with?('Debug')

    names = development(metadata).map { |plugin| plugin.fetch('name') }
    classes = []
    output = source.gsub(%r{^#if __has_include\(<([^/]+)/([^>]+)\.h>\)\n.*?^#endif\n}m) do |block|
      if names.include?(Regexp.last_match(1))
        classes << Regexp.last_match(2)
        ''
      else
        block
      end
    end
    classes.each do |name|
      pattern = /^\s*\[#{Regexp.escape(name)} registerWithRegistrar:.*?\];\n/
      raise "Missing Flutter registration for #{name}" unless output.scan(pattern).length == 1
      output = output.sub(pattern, '')
    end
    names.each do |name|
      raise "Unsupported Flutter import format for #{name}" if output.match?(%r{(?:<|@import )#{Regexp.escape(name)}(?:/|;)})
    end
    output
  end

  def self.generate(project, output, configuration)
    metadata = JSON.parse(File.read(File.join(project, '..', '.flutter-plugins-dependencies')))
    FileUtils.mkdir_p(output)
    %w[h m].each do |extension|
      name = "GeneratedPluginRegistrant.#{extension}"
      content = File.read(File.join(project, 'Runner', name))
      content = registry(content, metadata, configuration) if extension == 'm'
      destination = File.join(output, name)
      File.write(destination, content) unless File.exist?(destination) && File.read(destination) == content
    end
  end
end

if $PROGRAM_NAME == __FILE__
  WenkuPluginConfiguration.generate(ENV.fetch('SRCROOT'), ENV.fetch('DERIVED_FILE_DIR'), ENV.fetch('CONFIGURATION'))
end
