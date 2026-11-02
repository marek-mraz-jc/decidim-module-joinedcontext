# frozen_string_literal: true

require "spec_helper"

# expected.json is the harvester's own mapping run in Bento over input.json (generate.py beside it):
# the same record, pulled and pushed, is one entity.
describe Decidim::Joinedcontext::Mapper do
  subject(:mapper) { described_class.new(publication) }

  let(:expected) { JSON.parse(File.read(File.expand_path("../../../fixtures/harvester/expected.json", __dir__))) }
  let(:organization) { create(:organization, host: "participacia.example.org", default_locale: :en) }
  let(:process) do
    create(:participatory_process, :published, id: 901, organization:, slug: "lavicky", reference: "P-901", title: { en: "Lavičky pre mesto" },
                                               short_description: { en: "<p>Kde pribudnú lavičky</p>" }, start_date: Date.new(2026, 1, 1), end_date: Date.new(2099, 12, 31))
  end
  let!(:step) do
    create(:participatory_process_step, participatory_process: process, title: { en: "Hlasovanie" }, active: true, start_date: Time.utc(2026, 1, 1, 10), end_date: Time.utc(2099, 12, 31, 10))
  end
  let(:publication) { create(:joinedcontext_publication, participatory_space: process) }

  def expect_same(record, name, updated_at, only_push: [])
    record.update_columns(updated_at: Time.iso8601(updated_at)) # rubocop:disable Rails/SkipsModelValidations
    entity = mapper.entity(record.reload)
    wanted = expected.fetch(name).except("expiresAt")
    expect(entity.except("expiresAt", *only_push)).to eq(wanted)
  end

  it "agrees on a process" do
    process.update_columns(updated_at: Time.utc(2026, 10, 1, 10)) # rubocop:disable Rails/SkipsModelValidations
    expect(mapper.entity(process.reload).except("expiresAt")).to eq(expected.fetch("process").except("expiresAt"))
  end

  it "agrees on a result" do
    component = create(:accountability_component, id: 902, participatory_space: process)
    status = create(:status, component:, name: { en: "Prebieha" })
    result = create(:result, id: 903, component:, status:, progress: 40.5, title: { en: "Nové lavičky" }, description: { en: "<p>Napíšte na info@mesto.sk alebo +421905123456 či +421 905 123 456.</p>" },
                             start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 9, 1))
    result.update_columns(reference: "R-903") # rubocop:disable Rails/SkipsModelValidations
    expect_same(result, "result", "2026-10-02T06:30:00Z")
  end

  it "agrees on a proposal" do
    component = create(:proposal_component, id: 902, participatory_space: process)
    proposal = create(:proposal, id: 904, component:, title: { en: "Oprava chodníka" }, body: { en: "Chodník pri škole" }, address: "Námestie 1", latitude: 48.7, longitude: 19.1,
                                 published_at: Time.utc(2026, 9, 1, 8))
    proposal.update!(answered_at: Time.current, state_published_at: Time.current, proposal_state: Decidim::Proposals::ProposalState.find_by(component:, token: "accepted"))
    proposal.update_columns(reference: "N-904", proposal_votes_count: 7, likes_count: 2) # rubocop:disable Rails/SkipsModelValidations
    expect_same(proposal, "proposal", "2026-10-03T08:30:00Z", only_push: %w(stateLabel))
  end

  it "agrees on a budget project" do
    component = create(:budgets_component, id: 902, participatory_space: process)
    budget = create(:budget, id: 906, component:, title: { en: "Rozpočet 2026" }, total_budget: 50_000)
    project = create(:project, id: 905, budget:, budget_amount: 1200, title: { en: "Park" }, description: { en: "Nový park" }, selected_at: Time.current)
    project.update_columns(reference: "B-905") # rubocop:disable Rails/SkipsModelValidations
    expect_same(project, "project", "2026-10-04T08:30:00Z", only_push: %w(voteCount))
  end

  it "agrees on a meeting" do
    component = create(:meeting_component, id: 902, participatory_space: process)
    meeting = create(:meeting, :published, id: 907, component:, title: { en: "Verejné stretnutie" }, description: { en: "O lavičkách" }, start_time: Time.utc(2026, 5, 1, 16), end_time: Time.utc(2026, 5, 1, 18),
                                           address: "Radnica", location: { en: "Veľká sála" }, latitude: 48.7, longitude: 19.1, online_meeting_url: "https://meet.example.org/a", type_of_meeting: "hybrid",
                                           closed_at: Time.current, closing_visible: true, closing_report: { en: "Správa" }, attendees_count: 3)
    meeting.update_columns(reference: "M-907") # rubocop:disable Rails/SkipsModelValidations
    expect_same(meeting, "meeting", "2026-10-05T08:30:00Z", only_push: %w(closingReport attendeesCount))
  end
end
