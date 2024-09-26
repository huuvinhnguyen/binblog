class AddFingerprintTemplateToFingers < ActiveRecord::Migration[7.0]
  def change
    add_column :fingers, :fingerprint_template, :binary
    add_index :fingers, :fingerprint_template, unique: true
  end
end
