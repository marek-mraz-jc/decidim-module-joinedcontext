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
        batches(publication, mapper).each do |entities|
          client.write_entities(entities)
          count += entities.size
        end
        publication.update!(last_synced_at: Time.current, last_count: count, last_error: nil)
      rescue Client::Error => e
        publication.update!(last_error: e.message, last_attempt_at: Time.current)
        raise if e.is_a?(Client::Unavailable)
      end

      private

      # The gateway looks a Relationship's target up in the store, never in the batch that carries
      # it, so a record naming an entity of the open batch starts the next one.
      def batches(publication, mapper)
        Enumerator.new do |out|
          batch = []
          publication.records.lazy.select { |record| mapper.publishable?(record) }.each do |record|
            entity = mapper.entity(record)
            if batch.size == Client::BATCH || names_any?(entity, batch)
              out << batch
              batch = []
            end
            batch << entity
          end
          out << batch if batch.any?
        end
      end

      def names_any?(entity, batch)
        targets = entity.values.filter_map { |attribute| attribute["object"] if attribute.is_a?(Hash) }
        batch.any? { |held| targets.include?(held["id"]) }
      end
    end
  end
end
