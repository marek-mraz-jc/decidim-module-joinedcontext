# frozen_string_literal: true

module Decidim
  module Joinedcontext
    # One space's "Publish to context space" setting and the status of its last sync.
    class Publication < ApplicationRecord
      self.table_name = "decidim_joinedcontext_publications"

      COMPONENT_TYPES = %w(accountability proposals budgets meetings).freeze
      RECORDS = {
        "accountability" => ->(component) { Decidim::Accountability::Result.where(component:).order(Arel.sql("parent_id NULLS FIRST")) },
        "proposals" => ->(component) { Decidim::Proposals::Proposal.where(component:) },
        "budgets" => ->(component) { Decidim::Budgets::Project.where(budget: Decidim::Budgets::Budget.where(component:)) },
        "meetings" => ->(component) { Decidim::Meetings::Meeting.where(component:) }
      }.freeze

      belongs_to :participatory_space,
                 polymorphic: true,
                 foreign_key: "decidim_participatory_space_id",
                 foreign_type: "decidim_participatory_space_type"

      scope :active, -> { where(enabled: true) }

      validates :endpoint_name, inclusion: { in: ->(_) { Target.all.map(&:name) } }, if: :enabled?
      validate :only_known_component_types
      validate :only_public_spaces, if: :enabled?

      def self.for_space(space)
        active.find_by(participatory_space: space)
      end

      # The active publication that carries this record, or nil.
      def self.for_record(record)
        return for_space(record) if Mapper.space?(record)

        publication = for_space(record.component.participatory_space)
        publication if publication&.publishes?(record.component.manifest_name.to_s)
      end

      def self.private_space?(space)
        space.try(:private_space?) || false
      end

      def target
        Target.find(endpoint_name)
      end

      def active?
        enabled? && target.present? && !self.class.private_space?(participatory_space)
      end

      def publishes?(manifest_name)
        component_types.include?(manifest_name)
      end

      # Every record of a full pass, the space first and a parent before its child: a Relationship to an
      # Entity the broker lacks is refused (SyncJob keeps them in separate batches).
      def records
        Enumerator.new do |out|
          out << participatory_space
          participatory_space.components.published.where(manifest_name: component_types).find_each do |component|
            RECORDS.fetch(component.manifest_name).call(component).each { |record| out << record }
          end
        end
      end

      private

      def only_known_component_types
        errors.add(:component_types, :inclusion) unless component_types.is_a?(Array) && (component_types - COMPONENT_TYPES).empty?
      end

      def only_public_spaces
        errors.add(:enabled, :private_space) if self.class.private_space?(participatory_space)
      end
    end
  end
end
