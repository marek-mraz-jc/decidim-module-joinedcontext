# frozen_string_literal: true

class CreateDecidimJoinedcontextPublications < ActiveRecord::Migration[7.2]
  def change
    create_table :decidim_joinedcontext_publications do |t|
      t.references :decidim_participatory_space, polymorphic: true, null: false, index: { unique: true, name: "index_decidim_joinedcontext_publications_on_space" }
      t.boolean :enabled, null: false, default: false
      t.string :endpoint_name
      t.jsonb :component_types, null: false, default: []
      t.datetime :last_synced_at
      t.integer :last_count
      t.string :last_error

      t.timestamps
    end
  end
end
