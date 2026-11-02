# frozen_string_literal: true

module Decidim
  module Joinedcontext
    module Admin
    end

    # The per-space setting in the admin panel.
    class AdminEngine < ::Rails::Engine
      isolate_namespace Decidim::Joinedcontext::Admin

      paths["db/migrate"] = nil
      paths["lib/tasks"] = nil

      routes do
        scope "/participatory_processes/:participatory_process_slug" do
          resource :publication, only: [:edit, :update], controller: "participatory_process_publications", as: :process_publication do
            post :sync
          end
        end

        scope "/assemblies/:assembly_slug" do
          resource :publication, only: [:edit, :update], controller: "assembly_publications", as: :assembly_publication do
            post :sync
          end
        end
      end

      initializer "decidim_joinedcontext.admin_mount" do
        Decidim::Core::Engine.routes do
          extend Decidim::Routes::LocaleRedirects

          scope "/:locale", **locale_scope_options do
            mount Decidim::Joinedcontext::AdminEngine, at: "/admin/joinedcontext", as: "decidim_admin_joinedcontext"
          end
        end
      end

      initializer "decidim_joinedcontext.admin_menus" do
        Decidim.menu :admin_participatory_process_menu do |menu|
          path = decidim_admin_joinedcontext.edit_process_publication_path(participatory_process_slug: current_participatory_space.slug)
          menu.add_item :joinedcontext_publication,
                        I18n.t("decidim.joinedcontext.admin.menu.publication"),
                        path,
                        active: is_active_link?(path),
                        icon_name: "share-line",
                        if: allowed_to?(:update, :process, process: current_participatory_space)
        end

        Decidim.menu :admin_assembly_menu do |menu|
          path = decidim_admin_joinedcontext.edit_assembly_publication_path(assembly_slug: current_participatory_space.slug)
          menu.add_item :joinedcontext_publication,
                        I18n.t("decidim.joinedcontext.admin.menu.publication"),
                        path,
                        active: is_active_link?(path),
                        icon_name: "share-line",
                        if: allowed_to?(:update, :assembly, assembly: current_participatory_space)
        end
      end

      def load_seed
        nil
      end
    end
  end
end
