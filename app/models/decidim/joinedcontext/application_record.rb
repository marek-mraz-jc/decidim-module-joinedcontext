# frozen_string_literal: true

module Decidim
  module Joinedcontext
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
