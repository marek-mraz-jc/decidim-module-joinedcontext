# frozen_string_literal: true

require "rails"
require "decidim/core"

module Decidim
  module Joinedcontext
    # Loads the hooks that turn a saved record into a sync.
    class Engine < ::Rails::Engine
      isolate_namespace Decidim::Joinedcontext

      # The image runs `db:migrate` on a read-only tree, so the migration stays in the gem.
      initializer "decidim_joinedcontext.migrations" do |app|
        app.config.paths["db/migrate"].concat(paths["db/migrate"].existent)
      end

      config.to_prepare do
        [
          "Decidim::ParticipatoryProcess", "Decidim::Assembly", "Decidim::Component", "Decidim::Moderation",
          "Decidim::Accountability::Result", "Decidim::Proposals::Proposal", "Decidim::Budgets::Project",
          "Decidim::Meetings::Meeting"
        ].each { |name| name.constantize.include(Decidim::Joinedcontext::Publishable) }
      end
    end
  end
end
