require "test_helper"

class TermsAcceptanceTest < ActiveSupport::TestCase
  test "records only version, local acceptance time, and application version" do
    acceptance = TermsAcceptance.accept_current!

    assert_equal TermsDocument.new.version, acceptance.terms_version
    assert acceptance.accepted_at
    assert_equal TermsDocument.application_version, acceptance.application_version
    assert_equal %w[accepted_at application_version created_at id terms_version updated_at], acceptance.attributes.keys.sort
  end

  test "a future terms version requires renewed acceptance" do
    TermsAcceptance.accept_current!
    future_terms = Struct.new(:version).new("2099-01-01")

    assert_not TermsAcceptance.current?(future_terms)
  end
end
