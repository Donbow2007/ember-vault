# Ruby 3.2+ exposes the RFC2396 parser as RFC2396_Parser, but Rails still
# references the legacy RFC2396_PARSER constant. Provide the compatibility alias
# before the app boots so route generation and URL helpers work reliably.
require "uri"

if defined?(URI::RFC2396_Parser) && !defined?(URI::RFC2396_PARSER)
  URI.const_set(:RFC2396_PARSER, URI::RFC2396_Parser.new)
end

if defined?(URI::RFC3986_Parser) && !defined?(URI::RFC3986_PARSER)
  URI.const_set(:RFC3986_PARSER, URI::RFC3986_Parser.new)
end
