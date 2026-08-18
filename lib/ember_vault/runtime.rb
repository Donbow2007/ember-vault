require "fileutils"
require "net/http"
require "open3"
require "securerandom"
require "time"

module EmberVault
  class Runtime
    APP_ROOT = File.expand_path("../..", __dir__)
    STORAGE_ROOT = ENV.fetch("EMBER_VAULT_DATA_DIR", File.join(APP_ROOT, "storage"))
    PID_PATH = File.join(STORAGE_ROOT, "ember-vault.pid")
    LOG_PATH = File.join(STORAGE_ROOT, "ember-vault.log")
    SECRET_PATH = File.join(STORAGE_ROOT, ".secret_key_base")
    UPDATE_LOCK_PATH = File.join(STORAGE_ROOT, ".update.lock")

    def initialize(output: $stdout)
      @output = output
      FileUtils.mkdir_p(STORAGE_ROOT)
    end

    def setup
      ensure_directories
      ensure_secret
      run!(%w[bundle install]) unless system("bundle", "check", chdir: APP_ROOT)
      run!(%w[npm ci --prefix vendor/map_indexer])
      run!(%w[bin/rails db:prepare], env: production_env)
      run!(%w[bin/rails assets:precompile], env: production_env.merge("SECRET_KEY_BASE_DUMMY" => "1"))
      say "Ember Vault setup complete."
    end

    def run_foreground
      ensure_directories
      ensure_secret
      Dir.chdir(APP_ROOT) do
        exec(production_env, "bin/rails", "server", "-e", "production", "-b", bind_address, "-p", port)
      end
    end

    def start
      return say("Ember Vault is already running as PID #{read_pid}.") if running?

      ensure_directories
      ensure_secret
      log = File.open(LOG_PATH, "a")
      options = Gem.win_platform? ? { new_pgroup: true } : { pgroup: true }
      pid = Process.spawn(production_env, "bin/rails", "server", "-e", "production", "-b", bind_address, "-p", port,
        chdir: APP_ROOT, out: log, err: log, **options)
      Process.detach(pid)
      File.write(PID_PATH, pid)
      say "Starting Ember Vault as PID #{pid}..."
      raise "Ember Vault did not become healthy. Check #{LOG_PATH}." unless wait_for_health

      say "Ember Vault is ready at http://#{display_host}:#{port}."
    end

    def stop
      return say("Ember Vault is not running.") unless running?

      pid = read_pid
      Process.kill(Gem.win_platform? ? "KILL" : "TERM", pid)
      50.times do
        break unless process_alive?(pid)
        sleep 0.1
      end
      Process.kill("KILL", pid) if process_alive?(pid)
      FileUtils.rm_f(PID_PATH)
      say "Ember Vault stopped."
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
      files = Dir.glob(File.join(STORAGE_ROOT, "*.sqlite3*")).select { |path| File.file?(path) }
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
      %w[archive_files content backups].each { |directory| FileUtils.mkdir_p(File.join(STORAGE_ROOT, directory)) }
    end

    def ensure_secret
      return if File.file?(SECRET_PATH)

      File.write(SECRET_PATH, SecureRandom.hex(64))
      File.chmod(0o600, SECRET_PATH) unless Gem.win_platform?
    end

    def production_env
      {
        "RAILS_ENV" => "production",
        "RACK_ENV" => "production",
        "SECRET_KEY_BASE" => File.read(SECRET_PATH).strip,
        "EMBER_VAULT_DATA_DIR" => STORAGE_ROOT,
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

    def read_pid
      Integer(File.read(PID_PATH).strip)
    rescue Errno::ENOENT, ArgumentError
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
