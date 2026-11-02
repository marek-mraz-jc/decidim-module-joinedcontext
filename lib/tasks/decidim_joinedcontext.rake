# frozen_string_literal: true

namespace :decidim_joinedcontext do
  desc "Queues the full pass of every active publication; the nightly CronJob runs this"
  task sync_all: :environment do
    Decidim::Joinedcontext::Publication.active.find_each { |publication| Decidim::Joinedcontext::SyncJob.perform_later(publication.id) }
  end
end
