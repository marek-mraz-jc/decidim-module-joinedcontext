# frozen_string_literal: true

require "spec_helper"

# The journey through a real browser: the admin turns the option on, the sync runs against a stubbed
# Endpoint, the status line reports it. Each state leaves a 1440 and a 400 px shot in SHOTS_DIR.
describe "Publish to context space" do
  include ActiveJob::TestHelper

  let(:organization) { create(:organization) }
  let(:process) { create(:participatory_process, :published, organization:) }
  let!(:component) { create(:accountability_component, participatory_space: process) }
  let!(:result) { create(:result, component:, title: { en: "Benches on the square" }) }
  let(:admin) { create(:process_admin, participatory_process: process, organization:) }
  let(:path) { "/en/admin/joinedcontext/participatory_processes/#{process.slug}/publication/edit" }

  def shots(state)
    dir = ENV.fetch("SHOTS_DIR", "tmp/shots")
    FileUtils.mkdir_p(dir)
    [1440, 400].each do |width|
      page.current_window.resize_to(width, 900)
      height = page.evaluate_script("document.documentElement.scrollHeight")
      page.current_window.resize_to(width, height)
      page.save_screenshot(File.expand_path("#{dir}/#{state}-#{width}.png")) # rubocop:disable Lint/Debugger
    end
    page.current_window.resize_to(1440, 900)
  end

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
    stub_token
    stub_request(:post, JoinedcontextHelpers::UPSERT).to_return(status: 204)
    admin.update!(confirmed_at: Time.current, admin_terms_accepted_at: Time.current)
    switch_to_host(organization.host)
    login_as admin, scope: :user
  end

  it "says what to do while no Endpoint is set up" do
    ENV["JOINEDCONTEXT_ENDPOINTS"] = "[]"
    visit path
    expect(page).to have_content("No Endpoint is set up")
    shots("no-endpoints")
  end

  it "turns on, syncs and reports" do
    visit "/en/admin/participatory_processes/#{process.slug}/edit"
    click_on "Publish to context space"
    expect(page).to have_content("Publishing is off")
    expect(page).to have_content("Not synced yet")
    expect(page).to have_content("for example")
    shots("empty")

    check "Publish this space"
    select "Participation", from: "Target Endpoint"
    check "Results and their progress"
    expect(page).to have_content("Nothing changes until you press Save")
    shots("filled")

    perform_enqueued_jobs { click_on "Save" }
    expect(page).to have_content("Setting saved")
    visit path
    expect(find_by_id("joinedcontext-status")).to have_content("2")
    expect(a_request(:post, JoinedcontextHelpers::UPSERT)).to have_been_requested.at_least_once
    shots("synced")
  end

  it "shows a refusal an admin can act on" do
    create(:joinedcontext_publication, participatory_space: process, component_types: ["accountability"])
    stub_request(:post, JoinedcontextHelpers::UPSERT).to_return(status: 403, body: { title: "Forbidden" }.to_json)
    visit path
    perform_enqueued_jobs { click_on "Sync now" }
    visit path
    expect(page).to have_css(".flash.alert, .callout.alert, [data-announcement]", text: "Ask your platform team to check its Policy")
    expect(find_by_id("joinedcontext-status")).to have_content("Last attempt")
    shots("refused")
  end

  it "shows a private space why it cannot be published" do
    process.update!(private_space: true)
    visit path
    expect(page).to have_content("cannot be published")
    expect(page).to have_no_button("Save")
    expect(page).to have_no_button("Sync now")
    shots("private")
  end
end
