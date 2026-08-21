require "test_helper"

class TermsControllerTest < ActionDispatch::IntegrationTest
  test "keeps the current terms accessible after setup" do
    TermsAcceptance.accept_current!

    get terms_url

    assert_response :success
    assert_select "h1", text: TermsDocument.new.title
    assert_select ".terms-document section", count: 16
    assert_select ".terms-header", text: /Accepted locally/
    assert_select "nav a[href='#{terms_path}']", text: "Terms"
  end
end
