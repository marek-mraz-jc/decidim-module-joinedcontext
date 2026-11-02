# frozen_string_literal: true

require "decidim/dev/common_rake"

desc "Generates the dummy application the specs run in"
task test_app: "decidim:generate_external_test_app" do
  # The generator writes dummy initiative handlers; this bundle has no decidim-initiatives.
  FileUtils.rm_f(Dir["spec/decidim_dummy_app/app/services/dummy_s*.rb"] + ["spec/decidim_dummy_app/config/initializers/decidim_initiatives.rb"])
end
