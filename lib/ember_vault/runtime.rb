require "fileutils"
require "json"
require "net/http"
require "open3"
require "securerandom"
require "socket"
require "time"
require_relative "paths"

module EmberVault
  class Runtime
    APP_ROOT = File.expand_path("../..", __dir__)
    STORAGE_ROOT = Paths.data_root.to_s
    PID_PATH = File.join(STORAGE_ROOT, "ember-vault.pid")
    LOG_PATH = File.join(STORAGE_ROOT, "ember-vault.log")
    SECRET_PATH = File.join(STORAGE_ROOT, ".secret_key_base")
    UPDATE_LOCK_PATH = File.join(STORAGE_ROOT, ".update.lock")

    def initialize(output: $stdout)
      @output = output
    end

    def setup
      ensure_directories
      ensure_secret
      run!(%w[bundle install]) unless system("bundle", "check", chdir: APP_ROOT)
      run!(%w[npm ci --prefix vendor/map_indexer])
      ensure_local_ai_runtime unless ENV["EMBER_VAULT_SKIP_LOCAL_AI_RUNTIME"] == "1"
      run!(%w[bin/rails db:prepare], env: production_env)
      run!(%w[bin/rails assets:precompile], env: production_env.merge("SECRET_KEY_BASE_DUMMY" => "1"))
      say "Ember Vault setup complete."
    end

    def run_foreground
      pid = nil
      ensure_directories
      ensure_secret
      raise "Ember Vault is already running as PID #{read_pid}." if running?

      say "Starting Ember Vault at http://#{display_host}:#{port}. Press Ctrl+C for a safe shutdown."
      pid = spawn_server
      write_pid(pid)
      wait_for_foreground_server(pid)
    ensure
      if pid
        FileUtils.rm_f(PID_PATH) if read_pid == pid
        flushed = checkpoint_and_flush
        say(flushed ? "Ember Vault stopped. It is now safe to eject portable storage." :
          "Ember Vault stopped. Use the operating system's eject command before removing storage.")
      end
    end

    def start
      return say("Ember Vault is already running as PID #{read_pid}.") if running?

      ensure_directories
      ensure_secret
      log = File.open(LOG_PATH, "a")
      begin
        pid = spawn_server(out: log, err: log)
      ensure
        log.close
      end
      Process.detach(pid)
      write_pid(pid)
      say "Starting Ember Vault as PID #{pid}..."
      raise "Ember Vault did not become healthy. Check #{LOG_PATH}." unless wait_for_health

      say "Ember Vault is ready at http://#{display_host}:#{port}."
    end

    def stop
      unless running?
        FileUtils.rm_f(PID_PATH)
        flushed = checkpoint_and_flush
        return say(flushed ? "Ember Vault is stopped. It is safe to eject portable storage." :
          "Ember Vault is stopped. Use the operating system's eject command before removing storage.")
      end

      pid = read_pid
      signal_process_group("TERM", pid)
      150.times do
        break unless process_alive?(pid)
        sleep 0.1
      end
      signal_process_group("KILL", pid) if process_alive?(pid)
      FileUtils.rm_f(PID_PATH)
      flushed = checkpoint_and_flush
      say(flushed ? "Ember Vault stopped. It is now safe to eject portable storage." :
        "Ember Vault stopped. Use the operating system's eject command before removing storage.")
    rescue Errno::ESRCH
      FileUtils.rm_f(PID_PATH)
      say "Ember Vault was already stopped."
    end

    def restart
      stop
      start
    end

    def status
      state = running? ? "running (PID #{read_pid})" : "stopped"
      say "Ember Vault #{version} is #{state}."
    end

    def update
      ensure_directories
      File.open(UPDATE_LOCK_PATH, File::RDWR | File::CREAT, 0o600) do |lock|
        raise "Another update is already running." unless lock.flock(File::LOCK_EX | File::LOCK_NB)

        perform_update
      end
    end

    def version
      File.read(File.join(APP_ROOT, "VERSION")).strip
    rescue Errno::ENOENT
      "development"
    end

    private

    def perform_update
      ensure_git_checkout!
      old_revision = capture!(%w[git rev-parse HEAD]).strip
      ensure_clean_checkout!
      run!(%w[git fetch --prune origin main])
      new_revision = capture!(%w[git rev-parse origin/main]).strip
      return say("Ember Vault is already current at #{old_revision[0, 8]}.") if old_revision == new_revision

      was_running = running?
      stop if was_running
      backup = backup_databases
      begin
        run!(%w[git merge --ff-only origin/main])
        setup
        start if was_running
        raise "Updated server failed its health check." if was_running && !healthy?
        say "Updated Ember Vault from #{old_revision[0, 8]} to #{new_revision[0, 8]}."
      rescue StandardError => error
        say "Update failed: #{error.message}. Rolling back..."
        stop if running?
        run!([ "git", "reset", "--keep", old_revision ])
        restore_databases(backup)
        setup
        start if was_running
        raise "Update rolled back to #{old_revision[0, 8]}."
      end
    end

    def ensure_git_checkout!
      raise "This installation is not a Git checkout and cannot use Git updates." unless File.directory?(File.join(APP_ROOT, ".git"))
    end

    def ensure_clean_checkout!
      changes = capture!(%w[git status --porcelain --untracked-files=no]).strip
      raise "Tracked source files have local changes. Commit or restore them before updating." unless changes.empty?
    end

    def backup_databases
      checkpoint_databases!
      files = database_files
      return nil if files.empty?

      destination = File.join(STORAGE_ROOT, "backups", Time.now.utc.strftime("%Y%m%dT%H%M%SZ"))
      FileUtils.mkdir_p(destination)
      files.each { |path| FileUtils.cp(path, destination) }
      say "Backed up #{files.size} database file(s) to #{destination}."
      destination
    end

    def restore_databases(backup)
      return unless backup && File.directory?(backup)

      Dir.glob(File.join(STORAGE_ROOT, "*.sqlite3*")).each { |path| FileUtils.rm_f(path) }
      Dir.glob(File.join(backup, "*")).each { |path| FileUtils.cp(path, STORAGE_ROOT) }
      say "Restored databases from #{backup}."
    end

    def ensure_directories
      Paths.prepare!
    end

    def ensure_local_ai_runtime
      return if executable_on_path?(Gem.win_platform? ? "llama-completion.exe" : "llama-completion")
      return if File.executable?(File.join(APP_ROOT, "vendor", "llama.cpp", "build", "bin", "llama-completion"))
      return say("NOTE: llama.cpp must be installed separately on Windows.") if Gem.win_platform?
      return say("NOTE: install llama.cpp with Homebrew to enable model answers.") if RUBY_PLATFORM.include?("darwin")

      source = File.join(APP_ROOT, "vendor", "llama.cpp")
      if File.directory?(File.join(source, ".git"))
        run!([ "git", "-C", source, "pull", "--ff-only" ])
      else
        run!([ "git", "clone", "--depth", "1", "https://github.com/ggml-org/llama.cpp.git", source ])
      end
      run!([ "cmake", "-S", source, "-B", File.join(source, "build"), "-DGGML_NATIVE=ON", "-DGGML_BUILD_TESTS=OFF", "-DGGML_BUILD_EXAMPLES=OFF", "-DLLAMA_BUILD_EXAMPLES=OFF", "-DLLAMA_BUILD_TOOLS=ON" ])
      run!([ "cmake", "--build", File.join(source, "build"), "--target", "llama-completion", "--parallel", "1" ])
    rescue StandardError => error
      say "NOTE: local AI runtime setup failed (#{error.message}); cited source mode remains available."
    end

    def executable_on_path?(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
        candidate = File.join(directory, name)
        File.file?(candidate) && File.executable?(candidate)
      end
    end

    def ensure_secret
      return if File.file?(SECRET_PATH)

      File.write(SECRET_PATH, SecureRandom.hex(64))
      File.chmod(0o600, SECRET_PATH) unless Gem.win_platform?
    end

    def spawn_server(out: nil, err: nil)
      options = Gem.win_platform? ? { new_pgroup: true } : { pgroup: true }
      options[:out] = out if out
      options[:err] = err if err
      Process.spawn(production_env, "bin/rails", "server", "-e", "production", "-b", bind_address, "-p", port,
        chdir: APP_ROOT, **options)
    end

    def wait_for_foreground_server(pid)
      previous_handlers = {}
      %w[INT TERM].each do |signal|
        previous_handlers[signal] = Signal.trap(signal) { signal_process_group("TERM", pid) }
      end
      Process.wait(pid)
    rescue Errno::ECHILD
      nil
    ensure
      previous_handlers&.each { |signal, handler| Signal.trap(signal, handler) }
    end

    def signal_process_group(signal, pid)
      Process.kill(signal, Gem.win_platform? ? pid : -pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    def database_files
      Dir.glob(File.join(STORAGE_ROOT, "*.sqlite3")).select { |path| File.file?(path) }
    end

    def checkpoint_databases!
      require "sqlite3"
      database_files.each do |path|
        database = nil
        database = SQLite3::Database.new(path)
        database.busy_timeout(5_000)
        result = database.execute("PRAGMA wal_checkpoint(TRUNCATE)").first
        raise "SQLite checkpoint remained busy for #{File.basename(path)}" if result && result.first.to_i.positive?
      ensure
        database&.close
      end
    end

    def checkpoint_and_flush
      checkpoint_databases!
      database_files.each { |path| File.open(path, "r+b", &:fsync) }
      system("sync", out: File::NULL, err: File::NULL) unless Gem.win_platform?
      true
    rescue LoadError, StandardError => error
      say "WARNING: storage flush could not be confirmed (#{error.message}). Do not unplug the drive until the operating system says it is safe."
      false
    end

    def production_env
      {
        "RAILS_ENV" => "production",
        "RACK_ENV" => "production",
        "SECRET_KEY_BASE" => File.read(SECRET_PATH).strip,
        "EMBER_VAULT_DATA_DIR" => STORAGE_ROOT,
        "EMBER_VAULT_DATA_PATH" => STORAGE_ROOT,
        "EMBER_VAULT_PORTABLE" => ENV.fetch("EMBER_VAULT_PORTABLE", "0"),
        "SOLID_QUEUE_IN_PUMA" => "1",
        "RAILS_MAX_THREADS" => ENV.fetch("RAILS_MAX_THREADS", "2"),
        "JOB_CONCURRENCY" => ENV.fetch("JOB_CONCURRENCY", "1"),
        "PORT" => port
      }
    end

    def run!(command, env: {})
      say "==> #{command.join(" ")}"
      system(env, *command, chdir: APP_ROOT, exception: false).tap do |success|
        raise "Command failed: #{command.join(" ")}" unless success
      end
    end

    def capture!(command)
      output, status = Open3.capture2e(*command, chdir: APP_ROOT)
      raise "Command failed: #{command.join(" ")}\n#{output}" unless status.success?
      output
    end

    def running?
      pid = read_pid
      pid && process_alive?(pid)
    end

    def write_pid(pid)
      temporary_path = "#{PID_PATH}.#{Process.pid}.tmp"
      payload = JSON.generate(pid:, host: Socket.gethostname, app_root: APP_ROOT)
      File.open(temporary_path, "w", 0o600) do |file|
        file.write(payload)
        file.flush
        file.fsync
      end
      File.rename(temporary_path, PID_PATH)
    ensure
      FileUtils.rm_f(temporary_path) if temporary_path && File.file?(temporary_path)
    end

    def read_pid
      payload = File.read(PID_PATH).strip
      record = JSON.parse(payload)
      return Integer(record) unless record.is_a?(Hash)
      return nil unless record["host"] == Socket.gethostname && record["app_root"] == APP_ROOT

      Integer(record.fetch("pid"))
    rescue Errno::ENOENT, ArgumentError, JSON::ParserError, KeyError
      nil
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::EINVAL
      false
    rescue Errno::EPERM
      true
    end

    def wait_for_health
      60.times do
        return true if healthy?
        sleep 0.5
      end
      false
    end

    def healthy?
      response = Net::HTTP.start("127.0.0.1", port.to_i, open_timeout: 1, read_timeout: 2) do |http|
        http.get("/up", { "Host" => "localhost" })
      end
      response.is_a?(Net::HTTPSuccess)
    rescue SystemCallError, Timeout::Error
      false
    end

    def port
      ENV.fetch("PORT", "3000")
    end

    def bind_address
      ENV.fetch("BIND_ADDRESS", "0.0.0.0")
    end

    def display_host
      bind_address == "0.0.0.0" ? "localhost" : bind_address
    end

    def say(message)
      @output.puts(message)
    end
  end
end
