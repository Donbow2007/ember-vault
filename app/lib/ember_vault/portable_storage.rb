module EmberVault
  module PortableStorage
    module_function

    DIRECTORIES = %w[models maps database settings logs backups tmp].freeze

    def root
      configured = ENV["EMBER_VAULT_DATA_DIR"].presence
      return Pathname.new(configured).expand_path if configured

      Rails.root.join("storage")
    end

    def path(*parts)
      root.join(*parts)
    end

    def prepare!
      DIRECTORIES.each { |directory| FileUtils.mkdir_p(path(directory)) }
      root
    end
  end
end
