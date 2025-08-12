class CreateContents < ActiveRecord::Migration[8.0]
  def change
    create_table :contents do |t|
      t.text :body
      t.string :slug

      t.timestamps
    end
    add_index :contents, :slug, unique: true
  end
end
