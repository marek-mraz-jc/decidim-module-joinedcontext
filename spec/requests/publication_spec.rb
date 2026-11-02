# frozen_string_literal: true

require "spec_helper"

describe "the publication setting" do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:organization) { create(:organization) }
  let(:process) { create(:participatory_process, :published, organization:) }
  let(:path) { "/en/admin/joinedcontext/participatory_processes/#{process.slug}/publication" }
  let(:params) { { publication: { enabled: "1", endpoint_name: "participacia", component_types: ["", "accountability"] } } }

  before do
    host! organization.host
    https!
  end

  def sign_in_admin(user)
    user.update!(confirmed_at: Time.current, admin_terms_accepted_at: Time.current)
    sign_in user
  end

  shared_examples "refused" do
    it "shows nothing and changes nothing" do
      get "#{path}/edit"
      expect(response).to have_http_status(:found)
      patch(path, params:)
      expect(response).to have_http_status(:found)
      expect(Decidim::Joinedcontext::Publication.count).to eq(0)
    end
  end

  context "without a session" do
    it_behaves_like "refused"
  end

  context "as a citizen" do
    before { sign_in create(:user, :confirmed, organization:) }

    it_behaves_like "refused"
  end

  context "as a process moderator" do
    before { sign_in_admin create(:process_moderator, participatory_process: process, organization:) }

    it_behaves_like "refused"
  end

  context "as a process collaborator" do
    before { sign_in_admin create(:process_collaborator, participatory_process: process, organization:) }

    it_behaves_like "refused"
  end

  context "as the admin of another process" do
    before { sign_in_admin create(:process_admin, participatory_process: create(:participatory_process, organization:), organization:) }

    it_behaves_like "refused"
  end

  context "as an admin of another organization" do
    before { sign_in create(:user, :admin, :confirmed, organization: create(:organization)) }

    it_behaves_like "refused"
  end

  context "as the process admin" do
    before { sign_in_admin create(:process_admin, participatory_process: process, organization:) }

    it "offers the listed Endpoints with hints and a status line" do
      get "#{path}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Participation", "Not synced yet", "Sync now", "for example", "publication/sync")
      get "/en/admin/participatory_processes/#{process.slug}/edit"
      expect(response.body).to include("Publish to context space", "/en/admin/joinedcontext/participatory_processes/#{process.slug}/publication/edit")
    end

    it "says what to do when no Endpoint is set up" do
      ENV["JOINEDCONTEXT_ENDPOINTS"] = "[]"
      get "#{path}/edit"
      expect(response.body).to include("No Endpoint is set up")
    end

    it "saves and starts the first full pass" do
      expect { patch(path, params:) }.to have_enqueued_job(Decidim::Joinedcontext::SyncJob)
      publication = Decidim::Joinedcontext::Publication.last
      expect(publication).to have_attributes(enabled: true, endpoint_name: "participacia", component_types: ["accountability"], participatory_space: process)
    end

    it "checks the submitted Endpoint again and names the field" do
      params[:publication][:endpoint_name] = "https://evil.example.org"
      patch(path, params:)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Choose one of the listed Endpoints")
      expect(Decidim::Joinedcontext::Publication.count).to eq(0)
    end

    it "refuses an unknown component type" do
      params[:publication][:component_types] = ["surveys"]
      patch(path, params:)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "queues Sync now, and refuses it while off" do
      post "#{path}/sync"
      expect(flash[:alert]).to include("Turn publishing on")
      create(:joinedcontext_publication, participatory_space: process)
      expect { post "#{path}/sync" }.to have_enqueued_job(Decidim::Joinedcontext::SyncJob)
    end
  end

  context "as an assembly admin" do
    let(:assembly) { create(:assembly, :published, organization:) }

    before { sign_in_admin create(:assembly_admin, assembly:, organization:) }

    it "reaches the setting of the assembly and no process" do
      get "/en/admin/joinedcontext/assemblies/#{assembly.slug}/publication/edit"
      expect(response).to have_http_status(:ok)
      get "#{path}/edit"
      expect(response).to have_http_status(:found)
    end
  end
end
