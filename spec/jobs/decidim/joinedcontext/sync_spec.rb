# frozen_string_literal: true

require "spec_helper"

describe "publishing" do
  include ActiveJob::TestHelper

  let(:organization) { create(:organization) }
  let(:process) { create(:participatory_process, :published, organization:) }
  let!(:component) { create(:accountability_component, participatory_space: process) }
  let!(:result) { create(:result, component:, title: { en: "Benches" }) }
  let(:publication) { create(:joinedcontext_publication, participatory_space: process) }
  let(:result_id) { Decidim::Joinedcontext::Mapper.new(publication).entity_id(result) }

  before do
    stub_token
    stub_request(:post, JoinedcontextHelpers::UPSERT).to_return(status: 204)
    stub_request(:post, JoinedcontextHelpers::DELETE).to_return(status: 204)
  end

  describe Decidim::Joinedcontext::SyncJob do
    it "sends the space first, then its records, and writes the status" do
      sent = []
      stub_request(:post, JoinedcontextHelpers::UPSERT).to_return { |request| sent.concat(JSON.parse(request.body)) && { status: 204 } }
      described_class.perform_now(publication.id)
      expect(sent.pluck("type")).to eq(%w(ParticipatoryProcess Result))
      expect(publication.reload).to have_attributes(last_count: 2, last_error: nil)
      expect(publication.last_synced_at).to be_present
    end

    it "leaves out a component type the admin did not tick" do
      publication.update!(component_types: ["proposals"])
      described_class.perform_now(publication.id)
      expect(publication.reload.last_count).to eq(1)
    end

    it "keeps an actionable last error and does not retry a refusal" do
      stub_request(:post, JoinedcontextHelpers::UPSERT).to_return(status: 403, body: { title: "Forbidden" }.to_json)
      expect { described_class.perform_now(publication.id) }.not_to raise_error
      expect(publication.reload.last_error).to include("Forbidden", "Policy")
    end

    it "retries while the Endpoint is away" do
      stub_request(:post, JoinedcontextHelpers::UPSERT).to_return(status: 503)
      expect { described_class.perform_now(publication.id) }.to have_enqueued_job(described_class)
      expect(publication.reload.last_error).to include("503")
    end

    it "writes nothing for a switched-off publication" do
      publication.update!(enabled: false)
      described_class.perform_now(publication.id)
      expect(a_request(:post, JoinedcontextHelpers::UPSERT)).not_to have_been_requested
    end
  end

  describe Decidim::Joinedcontext::PublishRecordJob do
    it "deletes the entity of a record that left" do
      id = result_id
      klass = result.class.name
      record_id = result.id
      result.destroy!
      described_class.perform_now(publication.id, klass, record_id, id)
      expect(a_request(:post, JoinedcontextHelpers::DELETE).with(body: [id].to_json)).to have_been_requested
    end

    it "loads no class outside the list" do
      described_class.perform_now(publication.id, "Decidim::User", create(:user, organization:).id, "urn:x")
      expect(a_request(:post, JoinedcontextHelpers::UPSERT)).not_to have_been_requested
    end
  end

  describe "the commit hook" do
    before { publication }

    it "queues a result when it is saved" do
      expect { result.update!(progress: 50) }.to have_enqueued_job(Decidim::Joinedcontext::PublishRecordJob)
        .with(publication.id, "Decidim::Accountability::Result", result.id, result_id)
    end

    it "queues nothing for a type left out" do
      publication.update!(component_types: ["meetings"])
      expect { result.update!(progress: 50) }.not_to have_enqueued_job(Decidim::Joinedcontext::PublishRecordJob)
    end

    it "queues the record when moderation hides it" do
      proposal = create(:proposal, component: create(:proposal_component, participatory_space: process))
      moderation = create(:moderation, reportable: proposal)
      expect { moderation.update!(hidden_at: Time.current) }.to have_enqueued_job(Decidim::Joinedcontext::PublishRecordJob).at_least(:once)
    end

    it "queues the full pass when a component's settings change" do
      expect { component.update!(default_step_settings: { comments_blocked: true }) }.to have_enqueued_job(Decidim::Joinedcontext::SyncJob).with(publication.id)
    end

    it "never lets a failure reach the person saving" do
      allow(Decidim::Joinedcontext::Publication).to receive(:for_record).and_raise(ActiveRecord::StatementInvalid)
      expect { result.update!(progress: 50) }.not_to raise_error
    end
  end

  describe "the nightly task" do
    it "queues every active publication" do
      publication
      Rails.application.load_tasks if Rake::Task.tasks.empty?
      expect { Rake::Task["decidim_joinedcontext:sync_all"].execute }.to have_enqueued_job(Decidim::Joinedcontext::SyncJob).with(publication.id)
    end
  end
end
