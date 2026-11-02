# frozen_string_literal: true

require "spec_helper"

describe Decidim::Joinedcontext::Mapper do
  subject(:mapper) { described_class.new(publication) }

  let(:organization) { create(:organization, host: "participacia.example.org") }
  let(:process) { create(:participatory_process, :published, :with_steps, organization:, slug: "lavicky") }
  let(:publication) { create(:joinedcontext_publication, participatory_space: process) }

  def value(entity, name)
    entity.fetch(name).fetch("value")
  end

  describe "ids" do
    it "matches the harvester's id scheme" do
      assembly = create(:assembly, :published, organization:)
      expect(mapper.entity_id(process)).to eq("urn:ngsi-ld:ParticipatoryProcess:participacia:mesto-p#{process.id}")
      expect(mapper.entity_id(assembly)).to eq("urn:ngsi-ld:ParticipatoryProcess:participacia:mesto-a#{assembly.id}")
    end
  end

  describe "a result" do
    let(:component) { create(:accountability_component, participatory_space: process) }
    let(:status) { create(:status, component:, name: { en: "Prebieha" }) }
    let(:parent) { create(:result, component:) }
    let(:result) do
      create(:result, component:, status:, parent:, progress: 40.5, title: { en: "Nové lavičky" }, description: { en: "<p>Spýtajte sa na info@mesto.sk</p>" },
                      start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 9, 1))
    end

    it "carries the harvester's attributes" do
      entity = mapper.entity(result)
      expect(entity).to include("id" => "urn:ngsi-ld:Result:participacia:mesto-#{result.id}", "type" => "Result", "scope" => "/SK/BB/banska_bystrica")
      expect(value(entity, "name")).to eq("Nové lavičky")
      expect(value(entity, "description")).to eq("Spýtajte sa na")
      expect(value(entity, "progress")).to eq(40.5)
      expect(value(entity, "resultStatus")).to eq("Prebieha")
      expect(value(entity, "startDate")).to eq("2026-03-01")
      expect(value(entity, "url")).to eq("https://participacia.example.org/processes/lavicky/f/#{component.id}/results/#{result.id}")
      expect(entity["refParticipatoryProcess"]["object"]).to eq(mapper.entity_id(process))
      expect(entity["refParent"]["object"]).to eq(mapper.entity_id(parent))
      expect(Time.iso8601(entity["expiresAt"])).to be_within(1.minute).of(3.days.from_now)
    end
  end

  describe "a proposal" do
    let(:component) { create(:proposal_component, participatory_space: process) }
    let(:author) { create(:user, :confirmed, organization:, name: "Jana Tajna", email: "jana@tajna.sk") }
    let(:proposal) { create(:proposal, component:, users: [author], title: { en: "Oprava chodníka" }, body: { en: "Text" }) }
    let(:accepted) { Decidim::Proposals::ProposalState.find_by(component:, token: "accepted") }

    it "writes the published state and answer" do
      proposal.update!(answer: { en: "Schválené, zavolajte 0905 123 456" }, answered_at: Time.current, state_published_at: Time.current, proposal_state: accepted)
      entity = mapper.entity(proposal)
      expect(value(entity, "proposalState")).to eq("accepted")
      expect(value(entity, "proposalAnswer")).to eq("Schválené, zavolajte")
      expect(entity).to have_key("stateLabel")
    end

    it "keeps back an answer the admins have not published" do
      proposal.update!(answer: { en: "Tajné" }, answered_at: Time.current, state_published_at: nil, proposal_state: accepted)
      entity = mapper.entity(proposal)
      expect(value(entity, "proposalState")).to eq("not_answered")
      expect(entity).not_to have_key("proposalAnswer")
      expect(entity).not_to have_key("stateLabel")
    end

    it "keeps back votes the component hides" do
      expect(mapper.entity(proposal)).to have_key("voteCount")
      component.update!(step_settings: { process.active_step.id.to_s => { votes_hidden: true } })
      expect(mapper.entity(proposal.reload)).not_to have_key("voteCount")
    end

    it "carries no author, e-mail or phone" do
      text = mapper.entity(proposal).to_json
      expect(text).not_to include("Jana Tajna")
      expect(text).not_to include("jana@tajna.sk")
      expect(text).not_to match(/author|user|comment/i)
    end

    it "is not publishable as a draft or when hidden" do
      expect(mapper.publishable?(proposal)).to be(true)
      expect(mapper.publishable?(create(:proposal, :draft, component:))).to be(false)
      expect(mapper.publishable?(create(:proposal, :hidden, component:).reload)).to be(false)
    end
  end

  describe "a budget project" do
    let(:component) { create(:budgets_component, participatory_space: process) }
    let(:budget) { create(:budget, component:, title: { en: "Rozpočet 2026" }, total_budget: 50_000) }
    let(:project) { create(:project, budget:, budget_amount: 1200, title: { en: "Park" }) }

    it "writes amount and budget, and the vote total only while the component shows it" do
      component.update!(step_settings: { process.active_step.id.to_s => { show_votes: false } })
      entity = mapper.entity(project)
      expect(value(entity, "budgetAmount")).to eq(1200)
      expect(value(entity, "budgetTotal")).to eq(50_000)
      expect(value(entity, "budgetName")).to eq("Rozpočet 2026")
      expect(entity).not_to have_key("voteCount")

      component.update!(step_settings: { process.active_step.id.to_s => { show_votes: true } })
      expect(value(mapper.entity(project.reload), "voteCount")).to eq(0)
    end
  end

  describe "a meeting" do
    let(:component) { create(:meeting_component, participatory_space: process) }
    let(:meeting) { create(:meeting, :published, component:, title: { en: "Verejné stretnutie" }) }

    it "writes the closing report only once it is visible" do
      meeting.update!(closing_visible: false, closed_at: Time.current, closing_report: { en: "Tajná správa" }, attendees_count: 12)
      expect(mapper.entity(meeting)).not_to have_key("closingReport")

      meeting.update!(closing_visible: true)
      entity = mapper.entity(meeting)
      expect(value(entity, "closed")).to be(true)
      expect(value(entity, "closingReport")).to eq("Tajná správa")
      expect(value(entity, "attendeesCount")).to eq(12)
    end

    it "does not publish a private meeting nobody may watch" do
      expect(mapper.publishable?(meeting)).to be(true)
      meeting.update!(private_meeting: true, transparent: false)
      expect(mapper.publishable?(meeting)).to be(false)
    end
  end

  describe "the space" do
    it "writes its process entity with status and steps" do
      entity = mapper.entity(process)
      expect(entity["type"]).to eq("ParticipatoryProcess")
      expect(value(entity, "processType")).to eq("process")
      expect(value(entity, "status")).to eq("active")
      expect(value(entity, "steps").first).to include("active" => true)
      expect(entity).not_to have_key("refParticipatoryProcess")
    end

    it "publishes nothing of an unpublished or private space" do
      process.update!(published_at: nil)
      expect(mapper.publishable?(process)).to be(false)
      process.update!(published_at: Time.current, private_space: true)
      expect(mapper.publishable?(process)).to be(false)
    end
  end
end
