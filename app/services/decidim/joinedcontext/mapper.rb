# frozen_string_literal: true

module Decidim
  module Joinedcontext
    # One Decidim record as the NGSI-LD Entity the harvester writes for it (seeds/decidim/pipeline.yaml):
    # same types, ids and attributes. Beside them it carries what only the database knows: the answer
    # to a proposal, a meeting's closing report and attendance.
    #
    # Personal data: this class is the one place fields leave Decidim. It reads no author, user,
    # comment, e-mail or phone field, and every free text goes through Text.clean.
    class Mapper
      TYPES = {
        "Decidim::ParticipatoryProcess" => "ParticipatoryProcess",
        "Decidim::Assembly" => "ParticipatoryProcess",
        "Decidim::Proposals::Proposal" => "Proposal",
        "Decidim::Budgets::Project" => "BudgetProject",
        "Decidim::Accountability::Result" => "Result",
        "Decidim::Meetings::Meeting" => "Meeting"
      }.freeze
      LEASE = 3.days
      PATHS = { "Decidim::ParticipatoryProcess" => "processes", "Decidim::Assembly" => "assemblies" }.freeze
      MEETING_TYPES = %w(in_person online hybrid).freeze
      LATITUDES = (47.7..49.7)
      LONGITUDES = (16.8..22.6)

      def self.known?(record)
        TYPES.has_key?(record.class.name)
      end

      def self.space?(record)
        PATHS.has_key?(record.class.name)
      end

      def initialize(publication)
        @target = publication.target
        @space = publication.participatory_space
        @organization = @space.organization
      end

      def entity_id(record)
        local = self.class.space?(record) ? "#{kind(record).first}#{record.id}" : record.id
        "urn:ngsi-ld:#{TYPES.fetch(record.class.name)}:#{target.space}:#{target.instance}-#{local}"
      end

      # Only what an anonymous visitor reads on the site leaves it.
      def publishable?(record)
        return false unless space.published? && !Publication.private_space?(space)
        return true if self.class.space?(record)
        return false if record.try(:deleted?) || record.try(:emendation?)

        record.visible? && !(record.is_a?(Decidim::Meetings::Meeting) && hidden_meeting?(record))
      end

      def entity(record)
        common(record).merge(own(record)).compact
      end

      private

      attr_reader :target, :space, :organization

      def own(record)
        case record
        when Decidim::Proposals::Proposal then proposal(record)
        when Decidim::Budgets::Project then project(record)
        when Decidim::Accountability::Result then result(record)
        when Decidim::Meetings::Meeting then meeting(record)
        else space_entity(record)
        end
      end

      def common(record)
        {
          "id" => entity_id(record),
          "type" => TYPES.fetch(record.class.name),
          "scope" => target.scope,
          "refParticipatoryProcess" => (relationship(entity_id(space)) unless self.class.space?(record)),
          "source" => prop(base),
          "dataProvider" => prop(target.provider),
          "sourceId" => prop(record.id.to_s),
          "reference" => prop(record.try(:reference)),
          "category" => prop(category(record)),
          "dateModified" => prop(instant(record.updated_at)),
          "expiresAt" => instant(LEASE.from_now)
        }
      end

      def space_entity(record)
        steps = record.try(:steps).to_a.sort_by(&:position)
        {
          "name" => prop(tr(record.title)),
          "description" => prop(tr(record.short_description)),
          "processType" => prop(kind(record)),
          "status" => prop(status(record)),
          "startDate" => prop(dated(record.try(:start_date))),
          "endDate" => prop(dated(record.try(:end_date))),
          "activeStep" => prop(tr(steps.find(&:active?)&.title)),
          "steps" => prop(steps.map { |step| step(step) }.presence),
          "url" => prop(page(record))
        }
      end

      def step(step)
        {
          "title" => tr(step.title), "startDate" => dated(step.start_date), "endDate" => dated(step.end_date),
          "active" => step.active? || false
        }.compact
      end

      def status(record)
        return unless record.is_a?(Decidim::ParticipatoryProcess)
        return "upcoming" if record.start_date&.future?
        return "past" if record.end_date&.past?

        "active"
      end

      def proposal(record)
        settings = record.component.current_settings
        answer = record.answered? && record.published_state? ? record.answer : nil
        {
          "name" => prop(tr(record.title)),
          "description" => prop(tr(record.body)),
          "proposalState" => prop(record.withdrawn? ? "withdrawn" : record.state || "not_answered"),
          "stateLabel" => prop((tr(record.proposal_state&.title) if record.published_state?)),
          "proposalAnswer" => prop(tr(answer)),
          "voteCount" => prop((record.proposal_votes_count unless settings.votes_hidden?)),
          "endorsementsCount" => prop(record.likes_count),
          "official" => prop(record.official?),
          "address" => address(record.address, nil),
          "location" => point(record),
          "url" => prop("#{component_page(record)}/proposals/#{record.id}"),
          "dateCreated" => prop(instant(record.published_at))
        }
      end

      def project(record)
        budget = record.budget
        {
          "name" => prop(tr(record.title)),
          "description" => prop(tr(record.description)),
          "budgetAmount" => prop(record.budget_amount),
          "selected" => prop(record.selected?),
          "voteCount" => prop((record.confirmed_orders_count if record.component.current_settings.show_votes?)),
          "budgetName" => prop(tr(budget.title)),
          "budgetTotal" => prop(budget.total_budget),
          "url" => prop("#{component_page(record)}/budgets/#{budget.id}/projects/#{record.id}")
        }
      end

      def result(record)
        progress = record.progress&.to_f
        {
          "name" => prop(tr(record.title)),
          "description" => prop(tr(record.description)),
          "progress" => prop((progress if progress&.between?(0, 100))),
          "resultStatus" => prop(tr(record.status&.name)),
          "startDate" => prop(dated(record.start_date)),
          "endDate" => prop(dated(record.end_date)),
          "refParent" => (relationship(entity_id(record.parent)) if record.parent),
          "url" => prop("#{component_page(record)}/results/#{record.id}")
        }
      end

      def meeting(record)
        reported = record.closing_visible?
        {
          "name" => prop(tr(record.title)),
          "description" => prop(tr(record.description)),
          "startDate" => prop(dated(record.start_time)),
          "endDate" => prop(dated(record.end_time)),
          "meetingType" => prop(record.type_of_meeting.to_s.presence_in(MEETING_TYPES)),
          "address" => address(record.address, tr(record.location)),
          "location" => point(record),
          "onlineUrl" => prop(record.online_meeting_url.to_s[%r{\Ahttps://.*}]),
          "closed" => prop(record.closed?),
          "closingReport" => prop((tr(record.closing_report) if reported)),
          "attendeesCount" => prop((record.attendees_count if reported)),
          "url" => prop("#{component_page(record)}/meetings/#{record.id}")
        }
      end

      # Same rule as the public list: a private meeting nobody may watch, a withdrawn one.
      def hidden_meeting?(record)
        (record.private_meeting? && !record.transparent?) || record.withdrawn?
      end

      def kind(record)
        record.is_a?(Decidim::Assembly) ? "assembly" : "process"
      end

      def base
        "https://#{organization.host}"
      end

      def page(record)
        "#{base}/#{PATHS.fetch(record.class.name)}/#{record.slug}"
      end

      def component_page(record)
        "#{page(space)}/f/#{record.component.id}"
      end

      def category(record)
        tr(record.try(:taxonomies)&.first&.name || record.try(:category)&.name)
      end

      # A translated column in the organization's language, else the first language holding text.
      def tr(value)
        return if value.nil?

        values = value.with_indifferent_access
        machine = values.fetch(:machine_translations, {})
        Text.clean(values[organization.default_locale].presence || machine[organization.default_locale].presence ||
                   values.except(:machine_translations).values.find(&:present?))
      end

      def prop(value)
        { "type" => "Property", "value" => value } unless value.nil?
      end

      def relationship(object)
        { "type" => "Relationship", "object" => object }
      end

      def instant(time)
        time&.utc&.strftime("%Y-%m-%dT%H:%M:%SZ")
      end

      def dated(value)
        value&.iso8601
      end

      def address(street, place)
        parts = [Text.clean(street), place].compact
        return if parts.empty?

        prop("streetAddress" => parts.join(", "), "addressLocality" => target.locality, "addressCountry" => "SK")
      end

      def point(record)
        latitude = record.latitude
        longitude = record.longitude
        return unless LATITUDES.cover?(latitude) && LONGITUDES.cover?(longitude)

        { "type" => "GeoProperty", "value" => { "type" => "Point", "coordinates" => [longitude, latitude] } }
      end
    end
  end
end
