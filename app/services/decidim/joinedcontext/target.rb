# frozen_string_literal: true

module Decidim
  module Joinedcontext
    # A write Endpoint this installation may publish to. The deployment names them in
    # JOINEDCONTEXT_ENDPOINTS, a JSON list; an admin only picks one, so no address comes from a form.
    # A row outside https://JOINEDCONTEXT_GATEWAY_HOST never loads.
    class Target
      FIELDS = %w(name title url space instance scope locality provider).freeze

      attr_reader(*FIELDS)

      def self.all
        rows = JSON.parse(ENV.fetch("JOINEDCONTEXT_ENDPOINTS", "[]"))
        rows.map { |row| new(row) }.select(&:allowed?)
      rescue JSON::ParserError, TypeError, ArgumentError, KeyError
        Rails.logger.warn("joinedcontext: JOINEDCONTEXT_ENDPOINTS is not a list of Endpoints")
        []
      end

      def self.find(name)
        all.find { |target| target.name == name }
      end

      def initialize(row)
        FIELDS.each { |field| instance_variable_set("@#{field}", row.fetch(field).to_s) }
      end

      def allowed?
        uri = URI.parse(url)
        uri.is_a?(URI::HTTPS) && uri.host.present? && uri.host == ENV.fetch("JOINEDCONTEXT_GATEWAY_HOST", nil)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
