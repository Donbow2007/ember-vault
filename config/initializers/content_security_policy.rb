# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  # The browser application is deliberately air-gapped. Content downloads are
  # performed by server-side jobs and do not require relaxing this policy.
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.connect_src :self
    policy.font_src :self, :data
    policy.form_action :self
    policy.frame_ancestors :self
    policy.frame_src :self
    policy.img_src :self, :data, :blob
    policy.manifest_src :self
    policy.media_src :self, :blob
    policy.object_src :none
    policy.script_src :self
    # A few progress indicators use server-generated inline width values.
    policy.style_src :self, :unsafe_inline
    policy.worker_src :self, :blob
  end

  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_report_only = false
end
