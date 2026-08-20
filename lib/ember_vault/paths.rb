require "fileutils"
require "pathname"

module EmberVault
  module Paths
    module_function

    APP_ROOT = Pathname.new(File.expand_path("../..", __dir__)).freeze
    LEGACY_STORAGE_ROOT = APP_ROOT.join("storage").freeze
    DATA_ENVIRONMENT_VARIABLES = %w[EMBER_VAULT_DATA_PATH EMBER_VAULT_DATA_DIR].freeze

    def app_root
      APP_ROOT
    end

    def data_root
      configured = DATA_ENVIRONMENT_VARIABLES.filter_map do |name|
        value = ENV[name].to_s.strip
        value unless value.empty?
      end.first
      Pathname.new(configured || LEGACY_STORAGE_ROOT).expand_path.cleanpath
    end

    def archive_files
      data_root.join("archive_files")
    end

    def content
      data_root.join("content")
    end

    def content_for(kind)
      content.join(kind.to_s)
    end

    def models
      data_root.join("models")
    end

    def backups
      data_root.join("backups")
    end

    def config
      data_root.join("config")
    end

    def logs
      data_root.join("logs")
    end

    def run
      data_root.join("run")
    end

    def prepare!
      [ data_root, archive_files, content, models, backups, config, logs, run ].each { |path| FileUtils.mkdir_p(path) }
      ensure_writable!
      data_root
    end

    def ensure_writable!
      FileUtils.mkdir_p(data_root)
      probe = data_root.join(".ember-vault-write-test-#{Process.pid}")
      File.open(probe, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write("ok")
        file.flush
        file.fsync
      end
      true
    rescue Errno::EROFS, Errno::EACCES, Errno::EPERM, Errno::ENOSPC => error
      raise IOError, "Ember Vault data storage is not writable: #{data_root} (#{error.message})"
    ensure
      File.delete(probe) if probe && File.file?(probe)
    end

    # New database records contain paths relative to the data root. Existing
    # records beginning with storage/ are remapped into the configured data
    # root so an older archive can be copied to a portable drive unchanged.
    def resolve(stored_path)
      value = Pathname.new(stored_path.to_s)
      raise ArgumentError, "Stored path is blank" if stored_path.to_s.strip.empty?
      raise ArgumentError, "Absolute stored paths are not portable" if value.absolute?

      parts = value.each_filename.to_a
      parts.shift if parts.first == "storage"
      candidate = data_root.join(*parts).cleanpath
      raise ArgumentError, "Stored path escapes the Ember Vault data directory" unless within?(candidate, data_root)

      candidate
    end

    def relative(path)
      candidate = Pathname.new(path).expand_path.cleanpath
      raise ArgumentError, "Path is outside the Ember Vault data directory" unless within?(candidate, data_root)

      candidate.relative_path_from(data_root).to_s
    end

    def within?(path, root)
      path = Pathname.new(path).expand_path.cleanpath
      root = Pathname.new(root).expand_path.cleanpath
      path == root || path.to_s.start_with?("#{root}#{File::SEPARATOR}")
    end

    def find_executable(name, override: nil)
      requested = override.to_s.strip
      return requested unless requested.empty? || !File.file?(requested) || !File.executable?(requested)

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
        executable_names(name).each do |executable_name|
          candidate = File.join(directory, executable_name)
          return candidate if File.file?(candidate) && File.executable?(candidate)
        end
      end
      nil
    end

    def executable_names(name)
      return [ name ] unless Gem.win_platform?

      extensions = ENV.fetch("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(";")
      [ name, *extensions.map { |extension| "#{name}#{extension.downcase}" } ]
    end
  end
end
