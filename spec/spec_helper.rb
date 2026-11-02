# frozen_string_literal: true

require "decidim/dev"

ENV["ENGINE_ROOT"] = File.dirname(__dir__)
Decidim::Dev.dummy_app_path = File.expand_path(File.join(__dir__, "decidim_dummy_app"))

require "decidim/dev/test/base_spec_helper"
require "webmock/rspec"

module JoinedcontextHelpers
  GATEWAY = "gateway.example.org"
  ENDPOINT = "https://#{GATEWAY}/api/endpoint/abc234".freeze
  TOKEN_URL = "https://sso.example.org/realms/r/protocol/openid-connect/token"
  UPSERT = "#{ENDPOINT}/ngsi-ld/v1/entityOperations/upsert?options=update".freeze
  DELETE = "#{ENDPOINT}/ngsi-ld/v1/entityOperations/delete".freeze
  TARGET = {
    "name" => "participacia", "title" => "Participation", "url" => ENDPOINT, "space" => "participacia", "instance" => "mesto",
    "scope" => "/SK/BB/banska_bystrica", "locality" => "Banská Bystrica", "provider" => "Mesto Banská Bystrica"
  }.freeze

  def stub_token(token: "t0k3n")
    stub_request(:post, TOKEN_URL).to_return(status: 200, body: { access_token: token, expires_in: 300 }.to_json)
  end
end

RSpec.configure do |config|
  config.include JoinedcontextHelpers

  config.around do |example|
    keep = ENV.to_h
    ENV.update(
      "JOINEDCONTEXT_ENDPOINTS" => [JoinedcontextHelpers::TARGET].to_json,
      "JOINEDCONTEXT_GATEWAY_HOST" => JoinedcontextHelpers::GATEWAY,
      "JOINEDCONTEXT_TOKEN_URL" => JoinedcontextHelpers::TOKEN_URL,
      "JOINEDCONTEXT_CLIENT_ID" => "decidim-publisher",
      "JOINEDCONTEXT_CLIENT_SECRET" => "s3cr3t-value"
    )
    Decidim::Joinedcontext::Client::TOKENS.clear
    example.run
  ensure
    ENV.replace(keep)
  end
end
