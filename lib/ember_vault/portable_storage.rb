module EmberVault
  module PortableStorage
    module_function

    def root
      configured = ENV["EMBER_VAULT_DATA_DIR"].presence
      return Pathname.new(configured).expand_path if configured

      Rails.root.join("storage")
    end

    def path(*parts)
      root.join(*parts)
    end

    def prepare!
      %w[models content maps backups tmp].each { |directory| FileUtils.mkdir_p(path(directory)) }
      root
    end
  end
end
