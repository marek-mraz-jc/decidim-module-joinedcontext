# frozen_string_literal: true

require "spec_helper"

describe Decidim::Joinedcontext::Publication do
  let(:process) { create(:participatory_process, :published) }

  it "accepts only a listed Endpoint and known component types" do
    expect(build(:joinedcontext_publication, participatory_space: process, endpoint_name: "other")).not_to be_valid
    expect(build(:joinedcontext_publication, participatory_space: process, component_types: ["surveys"])).not_to be_valid
    expect(build(:joinedcontext_publication, participatory_space: process)).to be_valid
  end

  it "refuses a private space" do
    process.update!(private_space: true)
    expect(build(:joinedcontext_publication, participatory_space: process)).not_to be_valid
  end

  it "stays inactive once the Endpoint leaves the list" do
    publication = create(:joinedcontext_publication, participatory_space: process)
    ENV["JOINEDCONTEXT_ENDPOINTS"] = "[]"
    expect(publication.reload).not_to be_active
  end
end
