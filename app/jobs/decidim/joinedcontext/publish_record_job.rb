# frozen_string_literal: true

module Decidim
  module Joinedcontext
    # One saved record: written while the public may see it, deleted once they may not.
    class PublishRecordJob < ApplicationJob
      queue_as :default

      discard_on ActiveRecord::RecordNotFound
      retry_on Client::Unavailable, wait: :polynomially_longer, attempts: 5

      def perform(publication_id, class_name, record_id, entity_id)
        publication = Publication.find(publication_id)
        return unless publication.active?

        mapper = Mapper.new(publication)
        client = Client.new(publication.target)
        return unless Mapper::TYPES.has_key?(class_name)

        record = class_name.constantize.find_by(id: record_id)
        if record && mapper.publishable?(record)
          client.write_entities([mapper.entity(record)])
        else
          client.delete_entities([entity_id])
        end
        publication.update!(last_synced_at: Time.current, last_error: nil)
      rescue Client::Error => e
        publication.update!(last_error: e.message)
        raise if e.is_a?(Client::Unavailable)
      end
    end
  end
end
