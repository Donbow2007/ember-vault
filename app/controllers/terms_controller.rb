class TermsController < ApplicationController
  def show
    @terms = TermsDocument.new
    @acceptance = TermsAcceptance.find_by(terms_version: @terms.version)
  end
end
