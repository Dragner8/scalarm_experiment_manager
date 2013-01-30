class AddSentAtToExperimentInstances < ActiveRecord::Migration
  def self.up
    add_column :experiment_instances, :sent_at, :timestamp
  end

  def self.down
    remove_column :experiment_instances, :sent_at
  end
end
