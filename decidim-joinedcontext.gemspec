# frozen_string_literal: true

$LOAD_PATH.push File.expand_path("lib", __dir__)

require "decidim/joinedcontext/version"

Gem::Specification.new do |s|
  s.name = "decidim-joinedcontext"
  s.version = Decidim::Joinedcontext::VERSION
  s.authors = ["joinedcontext platform"]
  s.license = "AGPL-3.0-or-later"
  s.homepage = "https://github.com/marek-mraz-jc/decidim-module-joinedcontext"
  s.summary = "Publishes the outputs of a participatory space to a joinedcontext context space"
  s.description = "Per participatory process and assembly, an admin option syncs results, proposal " \
                  "answers, budget projects and meeting outcomes as NGSI-LD entities through a write Endpoint."
  s.required_ruby_version = "~> 3.4.0"

  s.files = Dir["{app,config,db,lib}/**/*", "LICENSE-AGPLv3.txt", "Rakefile", "README.md"]

  s.add_dependency "decidim-accountability", Decidim::Joinedcontext::DECIDIM_VERSION
  s.add_dependency "decidim-admin", Decidim::Joinedcontext::DECIDIM_VERSION
  s.add_dependency "decidim-assemblies", Decidim::Joinedcontext::DECIDIM_VERSION
  s.add_dependency "decidim-budgets", Decidim::Joinedcontext::DECIDIM_VERSION
  s.add_dependency "decidim-core", Decidim::Joinedcontext::DECIDIM_VERSION
  s.add_dependency "decidim-meetings", Decidim::Joinedcontext::DECIDIM_VERSION
  s.add_dependency "decidim-participatory_processes", Decidim::Joinedcontext::DECIDIM_VERSION
  s.add_dependency "decidim-proposals", Decidim::Joinedcontext::DECIDIM_VERSION
  s.metadata["rubygems_mfa_required"] = "true"
end
