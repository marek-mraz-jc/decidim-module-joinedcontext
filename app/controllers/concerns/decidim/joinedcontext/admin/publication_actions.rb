# frozen_string_literal: true

module Decidim
  module Joinedcontext
    module Admin
      # The setting of one space, for the space's own admins: each controller names the permission.
      module PublicationActions
        extend ActiveSupport::Concern

        included do
          before_action :same_organization
          helper_method :publication, :targets, :update_path, :sync_path, :private_space?
        end

        class_methods do
          def local_prefixes
            super + ["decidim/joinedcontext/admin/publications"]
          end
        end

        def edit
          enforce_permission_to(*publication_permission)
        end

        def update
          enforce_permission_to(*publication_permission)
          publication.assign_attributes(publication_params)
          if publication.save
            Rails.logger.info("joinedcontext: user #{current_user.id} set publication #{publication.id}")
            SyncJob.perform_later(publication.id) if publication.active?
            flash[:notice] = t("decidim.joinedcontext.admin.publications.update.success")
            redirect_to edit_path
          else
            flash.now[:alert] = t("decidim.joinedcontext.admin.publications.update.error")
            render :edit, status: :unprocessable_content
          end
        end

        def sync
          enforce_permission_to(*publication_permission)
          if publication.active?
            SyncJob.perform_later(publication.id)
            flash[:notice] = t("decidim.joinedcontext.admin.publications.sync.success")
          else
            flash[:alert] = t("decidim.joinedcontext.admin.publications.sync.inactive")
          end
          redirect_to edit_path
        end

        private

        # Decidim's space permissions read `user.admin?` and never the user's organization.
        def same_organization
          raise Decidim::ActionForbidden unless current_user&.decidim_organization_id == current_organization.id
        end

        def publication
          @publication ||= Publication.find_or_initialize_by(participatory_space: current_participatory_space)
        end

        def targets
          @targets ||= Target.all
        end

        def private_space?
          Publication.private_space?(current_participatory_space)
        end

        def publication_params
          values = params.fetch(:publication, {}).permit(:enabled, :endpoint_name, component_types: [])
          values[:component_types] = Array(values[:component_types]).compact_blank
          values
        end
      end
    end
  end
end
