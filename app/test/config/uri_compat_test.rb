require "test_helper"

class UriCompatTest < ActiveSupport::TestCase
  test "Ruby 3.2 exposes the URI RFC2396 parser expected by Rails" do
    assert_not_nil URI::RFC2396_Parser
    assert_not_nil URI::RFC2396_PARSER
    assert_equal URI::RFC2396_Parser.new.class, URI::RFC2396_PARSER.class
  end
end
