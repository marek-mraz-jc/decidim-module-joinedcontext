# frozen_string_literal: true

module Decidim
  module Joinedcontext
    module Admin
      class ParticipatoryProcessPublicationsController < Decidim::Admin::ApplicationController
        include Decidim::ParticipatoryProcesses::Admin::Concerns::ParticipatoryProcessAdmin
        include PublicationActions

        private

        def publication_permission
          [:update, :process, { process: current_participatory_space }]
        end

        def edit_path
          decidim_admin_joinedcontext.edit_process_publication_path(participatory_process_slug: current_participatory_space.slug)
        end

        def update_path
          decidim_admin_joinedcontext.process_publication_path(participatory_process_slug: current_participatory_space.slug)
        end

        def sync_path
          decidim_admin_joinedcontext.sync_process_publication_path(participatory_process_slug: current_participatory_space.slug)
        end
      end
    end
  end
end
