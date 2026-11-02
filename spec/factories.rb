# frozen_string_literal: true

require "decidim/accountability/test/factories"
require "decidim/assemblies/test/factories"
require "decidim/budgets/test/factories"
require "decidim/core/test/factories"
require "decidim/meetings/test/factories"
require "decidim/participatory_processes/test/factories"
require "decidim/proposals/test/factories"

FactoryBot.define do
  factory :joinedcontext_publication, class: "Decidim::Joinedcontext::Publication" do
    participatory_space { association(:participatory_process, :published) }
    enabled { true }
    endpoint_name { "participacia" }
    component_types { Decidim::Joinedcontext::Publication::COMPONENT_TYPES }
  end
end
