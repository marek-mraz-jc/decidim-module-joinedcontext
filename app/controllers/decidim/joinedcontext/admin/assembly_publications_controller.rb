# frozen_string_literal: true

module Decidim
  module Joinedcontext
    module Admin
      class AssemblyPublicationsController < Decidim::Admin::ApplicationController
        include Decidim::Assemblies::Admin::Concerns::AssemblyAdmin
        include PublicationActions

        private

        def publication_permission
          [:update, :assembly, { assembly: current_participatory_space }]
        end

        def publication_path
          decidim_admin_joinedcontext.edit_assembly_publication_path(assembly_slug: current_participatory_space.slug)
        end

        def sync_path
          decidim_admin_joinedcontext.sync_assembly_publication_path(assembly_slug: current_participatory_space.slug)
        end
      end
    end
  end
end
