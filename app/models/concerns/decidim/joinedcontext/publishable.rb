# frozen_string_literal: true

module Decidim
  module Joinedcontext
    # Queues a sync when a record commits. Decidim emits no notification for a saved Result, Project
    # or answer, so the hook sits on the models. A failure here never reaches the person who saved.
    module Publishable
      extend ActiveSupport::Concern

      included do
        after_commit :queue_joinedcontext_sync
      end

      private

      def queue_joinedcontext_sync
        case self
        when Decidim::Moderation then queue_joinedcontext_record(reportable)
        when Decidim::Component then queue_joinedcontext_component
        else queue_joinedcontext_record(self)
        end
      rescue StandardError => e
        Rails.logger.warn("joinedcontext: no sync queued for #{self.class.name} #{id}: #{e.class}")
      end

      def queue_joinedcontext_record(record)
        return unless Mapper.known?(record)

        publication = Publication.for_record(record)
        return unless publication&.active?

        PublishRecordJob.perform_later(publication.id, record.class.name, record.id, Mapper.new(publication).entity_id(record))
      end

      # A setting such as show_votes decides what the records may say, so the component's records all move.
      def queue_joinedcontext_component
        publication = Publication.for_space(participatory_space)
        SyncJob.perform_later(publication.id) if publication&.active? && publication.publishes?(manifest_name.to_s)
      end
    end
  end
end
