class OnboardingController < ApplicationController
  def show
    @models = ModelCatalog.entries
    @installed = ModelCatalog.installed
    @map_count = MapPackDiscovery.new.call.compact.count
    @data_root = EmberVault::PortableStorage.root
  end

  def complete
    EmberVault::PortableStorage.prepare!
    File.write(EmberVault::PortableStorage.path("settings", "onboarding.complete"), Time.current.iso8601)
    redirect_to root_path, notice: "Ember Vault is ready for offline use."
  end
end
