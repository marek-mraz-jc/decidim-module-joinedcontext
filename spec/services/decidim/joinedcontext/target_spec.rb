# frozen_string_literal: true

require "spec_helper"

describe Decidim::Joinedcontext::Target do
  it "loads only https rows on the gateway host" do
    rows = [
      JoinedcontextHelpers::TARGET,
      JoinedcontextHelpers::TARGET.merge("name" => "elsewhere", "url" => "https://evil.example.org/api/endpoint/x"),
      JoinedcontextHelpers::TARGET.merge("name" => "plain", "url" => "http://#{JoinedcontextHelpers::GATEWAY}/api/endpoint/x")
    ]
    ENV["JOINEDCONTEXT_ENDPOINTS"] = rows.to_json
    expect(described_class.all.map(&:name)).to eq(["participacia"])
  end

  it "fails closed on a broken list" do
    ENV["JOINEDCONTEXT_ENDPOINTS"] = "not json"
    expect(described_class.all).to eq([])
    ENV["JOINEDCONTEXT_ENDPOINTS"] = [{ "name" => "only" }].to_json
    expect(described_class.all).to eq([])
  end
end
