# frozen_string_literal: true

require "spec_helper"

describe Decidim::Joinedcontext::Client do
  subject(:client) { described_class.new(target) }

  let(:target) { Decidim::Joinedcontext::Target.find("participacia") }
  let(:entity) { { "id" => "urn:ngsi-ld:Result:s:i-1", "type" => "Result" } }

  before { stub_token }

  it "sends the batch with a client-credentials token" do
    write = stub_request(:post, JoinedcontextHelpers::UPSERT)
            .with(headers: { "Authorization" => "Bearer t0k3n", "Content-Type" => "application/json" }, body: [entity].to_json)
            .to_return(status: 204)
    client.write_entities([entity])
    expect(write).to have_been_requested
    expect(a_request(:post, JoinedcontextHelpers::TOKEN_URL).with(body: hash_including("grant_type" => "client_credentials", "client_id" => "decidim-publisher"))).to have_been_requested
  end

  it "keeps the token between calls and asks again after a 401" do
    stub_request(:post, JoinedcontextHelpers::UPSERT).to_return({ status: 204 }, { status: 401 }, { status: 204 })
    client.write_entities([entity])
    client.write_entities([entity])
    expect(a_request(:post, JoinedcontextHelpers::TOKEN_URL)).to have_been_requested.twice
  end

  it "halves a batch over the body cap" do
    write = stub_request(:post, JoinedcontextHelpers::UPSERT).to_return(status: 204)
    client.write_entities(Array.new(4) { entity.merge("description" => "x" * 400.kilobytes) })
    expect(write).to have_been_requested.twice
  end

  it "names the first refusal of a 207" do
    body = { success: [], errors: [{ entityId: entity["id"], error: { title: "Bad attribute" } }] }.to_json
    stub_request(:post, JoinedcontextHelpers::UPSERT).to_return(status: 207, body:)
    expect { client.write_entities([entity]) }.to raise_error(described_class::Error, /1 of 1 records: Bad attribute/)
  end

  it "reports a refusal with the problem title and never as retryable" do
    stub_request(:post, JoinedcontextHelpers::UPSERT).to_return(status: 403, body: { title: "Forbidden", detail: "no grant" }.to_json)
    expect { client.write_entities([entity]) }.to raise_error(described_class::Error, /Forbidden: no grant/) do |error|
      expect(error).not_to be_a(described_class::Unavailable)
    end
  end

  it "treats 429, 5xx and a timeout as retryable" do
    stub_request(:post, JoinedcontextHelpers::UPSERT).to_return(status: 503)
    expect { client.write_entities([entity]) }.to raise_error(described_class::Unavailable)
    stub_request(:post, JoinedcontextHelpers::UPSERT).to_return(status: 429)
    expect { client.write_entities([entity]) }.to raise_error(described_class::Unavailable)
    stub_request(:post, JoinedcontextHelpers::UPSERT).to_timeout
    expect { client.write_entities([entity]) }.to raise_error(described_class::Unavailable)
  end

  it "drops an oversized answer" do
    stub_request(:post, JoinedcontextHelpers::UPSERT).to_return(status: 400, body: "x" * (described_class::MAX_ANSWER + 1))
    expect { client.write_entities([entity]) }.to raise_error(described_class::Unavailable, /too large/)
  end

  it "follows no redirect" do
    stub_request(:post, JoinedcontextHelpers::UPSERT).to_return(status: 302, headers: { "Location" => "https://evil.example.org/" })
    expect { client.write_entities([entity]) }.to raise_error(described_class::Error, /302/)
    expect(a_request(:any, "https://evil.example.org/")).not_to have_been_requested
  end

  it "keeps the client secret out of every error" do
    stub_request(:post, JoinedcontextHelpers::TOKEN_URL).to_return(status: 401, body: "client_secret=s3cr3t-value")
    expect { client.write_entities([entity]) }.to raise_error(described_class::Error) do |error|
      expect(error.message).not_to include("s3cr3t-value")
    end
  end

  it "refuses to send anything when the gateway host changed" do
    target
    ENV["JOINEDCONTEXT_GATEWAY_HOST"] = "other.example.org"
    expect { client.write_entities([entity]) }.to raise_error(described_class::Error, /allowed gateway host/)
    expect(a_request(:post, JoinedcontextHelpers::UPSERT)).not_to have_been_requested
  end

  it "deletes by id" do
    delete = stub_request(:post, JoinedcontextHelpers::DELETE).with(body: [entity["id"]].to_json).to_return(status: 204)
    client.delete_entities([entity["id"]])
    expect(delete).to have_been_requested
  end
end
