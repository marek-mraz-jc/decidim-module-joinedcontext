# frozen_string_literal: true

module Decidim
  module Joinedcontext
    # Free text on its way out: no HTML, no e-mail address, no phone number, 2000 characters at most.
    # The harvester's rule (seeds/decidim/pipeline.yaml), so pull and push write one text.
    module Text
      EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/
      PHONE = %r{(\+[0-9]{1,3}[ /]?|\b0)[0-9][0-9 /]{7,}[0-9]}
      LIMIT = 2000

      module_function

      def clean(value)
        return if value.nil?

        text = CGI.unescapeHTML(Rails::HTML5::FullSanitizer.new.sanitize(value.to_s).to_s)
        text = text.gsub(EMAIL, "").gsub(PHONE, "").gsub(/\s+/, " ").sub(/[\s,;:]+\z/, "").strip
        text.presence&.first(LIMIT)
      end
    end
  end
end
