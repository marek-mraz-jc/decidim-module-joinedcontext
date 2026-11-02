# frozen_string_literal: true

module Decidim
  module Joinedcontext
    # The full pass of one space: Sync now, the nightly task, a change of a component.
    class SyncJob < ApplicationJob
      queue_as :default

      discard_on ActiveRecord::RecordNotFound
      retry_on Client::Unavailable, wait: :polynomially_longer, attempts: 5

      def perform(publication_id)
        publication = Publication.find(publication_id)
        return unless publication.active?

        mapper = Mapper.new(publication)
        client = Client.new(publication.target)
        count = 0
        publication.records.lazy.select { |record| mapper.publishable?(record) }.each_slice(Client::BATCH) do |records|
          client.upsert(records.map { |record| mapper.entity(record) })
          count += records.size
        end
        publication.update!(last_synced_at: Time.current, last_count: count, last_error: nil)
      rescue Client::Error => e
        publication.update!(last_error: e.message)
        raise if e.is_a?(Client::Unavailable)
      end
    end
  end
end
