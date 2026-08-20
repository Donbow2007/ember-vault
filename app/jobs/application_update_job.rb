require "open3"

class ApplicationUpdateJob < ApplicationJob
  queue_as :default

  def perform
    update = ApplicationUpdate.new
    update.write_status(state: "running", message: "Downloading and preparing the latest version.")
    output, status = Open3.capture2e({ "EMBER_VAULT_DATA_DIR" => data_root }, Rails.root.join("bin/ember-vault").to_s, "update",
      chdir: Rails.root.to_s)
    if status.success?
      update.write_status(state: "complete", message: output.lines.last.to_s.strip.presence || "Update installed. Restarting Ember Vault.")
      Rails.root.join("tmp/restart.txt").touch
    else
      update.write_status(state: "failed", message: output.lines.last(8).join.strip)
    end
  rescue StandardError => error
    ApplicationUpdate.new.write_status(state: "failed", message: error.message)
  end

  private

  def data_root
    EmberVault::Paths.data_root.to_s
  end
end
