#Attributes:
#“_id”: ObjectId
#“index”: integer
#“experiment_id” - ObjectId
#“to_sent” - bool
#“sent_at”: timestamp
#“is_done”: bool
#“done_at”: timestamp
#“run_index”: integer
#“arguments”: string - list of concatenated parameter ids
#“values”: string - list of concatenated parameter values
#“result”: JSON structure generated by simulation

class SimulationRun < MongoActiveRecord

  attr_join :experiment, Experiment

  def self.for_experiment(experiment_id)
    @experiment_id = experiment_id

    self
  end

  def self.completed
    where(
        {is_done: true, is_error: {'$exists' => false}},
        {fields: %w(index arguments values result __hash_attributes)}
    )
  end

  def self.collection_name
    "experiment_instances_#{@experiment_id}"
  end

  def where(conditions, options)
    super(conditions, {sort: [['index', :asc]]}.merge(options))
  end

  def self.create_table_for_experiment(experiment_id)
    @experiment_id = experiment_id

    raise('No Simulation Run DB available') if collection.nil?

    %w(index is_done to_sent).each do |index_sym|
      unless collection.index_information.include?(index_sym.to_s)
        collection.create_index([[index_sym.to_s, Mongo::ASCENDING]])         
      end 
    end

    # sharding collection
    MongoActiveRecord.shard_collection collection_name
  end

  def save
    SimulationRun.for_experiment(experiment_id)
    super
  end

  def meet_constraints?(constraints)
    return true if constraints.blank?

    args = arguments.split(',')
    vals = values.split(',')
    constraints.each do |constraint|
      source_value = vals[args.index(constraint['source_parameter'])].to_f
      target_value = vals[args.index(constraint['target_parameter'])].to_f
      #Rails.logger.debug("Checkig if #{source_value} #{constraint['condition']} #{target_value}")
      unless source_value.send(constraint['condition'], target_value)
        return false
      end
    end

    true
  end

  def rollback!
    Rails.logger.warn("Rolling back SimulationRun: #{id}")

    self.to_sent = true
    experiment.progress_bar_update(self.index, 'rollback')
    self.save
  end

end

#Attributes:
#“_id”: ObjectId
#“index”: integer
#“experiment_id” - ObjectId
#“to_sent” - bool
#“sent_at”: timestamp
#“is_done”: bool
#“done_at”: timestamp
#“run_index”: integer
#“arguments”: string - list of concatenated parameter ids
#“values”: string - list of concatenated parameter values
#“result”: JSON structure generated by simulation
module SimulationRunModule

  def simulation_collection_name
    "experiment_instances_#{self.experiment_id}"
  end

  def simulation_collection
    MongoActiveRecord.get_collection(simulation_collection_name)
  end

  def create_simulation_table
    collection = simulation_collection

    raise('No Experiment Instance DB available') if collection.nil?

    collection.create_index([['index', Mongo::ASCENDING]])
    collection.create_index([['is_done', Mongo::ASCENDING]])
    collection.create_index([['to_sent', Mongo::ASCENDING]])

    # sharding collection
    cmd = BSON::OrderedHash.new
    cmd['enableSharding'] = collection.db.name
    begin
      MongoActiveRecord.execute_raw_command_on('admin', cmd)
    rescue Exception => e
      Rails.logger.error(e)
    end

    cmd = BSON::OrderedHash.new
    cmd['shardcollection'] = "#{collection.db.name}.#{simulation_collection_name}"
    cmd['key'] = {'index' => 1}
    begin
      MongoActiveRecord.execute_raw_command_on('admin', cmd)
    rescue Exception => e
      Rails.logger.error(e)
    end
  end

  #def find_simulations_by(query, options = { sort: [ ['id', :asc] ] })
  #  simulations = []
  #
  #  simulation_collection.find(query, options).each{|doc| simulations << ExperimentInstance.new(doc)}
  #
  #  simulations
  #end

  def find_simulation_docs_by(query, options = { sort: [ ['index', :asc] ] })
    simulations = []

    simulation_collection.find(query, options).each{ |doc| simulations << doc }

    simulations
  end

  #def simulations_count_with(query)
  #  simulation_collection.count(query: query)
  #end

  def save_simulation(simulation_doc)
    if simulation_doc.include?('_id')
      simulation_collection.update({'_id' => simulation_doc['_id']}, simulation_doc, {upsert: true})
    else
      simulation_collection.update({'index' => simulation_doc['index']}, simulation_doc, {upsert: true})
    end
  end

  #def is_simulation_ready_to_run(simulation_id)
  #  simulation_doc = simulation_collection.find_one({ index: simulation_id })
  #  simulation_doc.nil? or simulation_doc['to_sent']
  #end

  def create_new_simulation(simulation_id)
    simulation = generate_simulation_for(simulation_id)
    simulation.to_sent = false
    simulation.sent_at = Time.now
    Rails.logger.debug("Created simulation to save: #{simulation.inspect} --- #{simulation.save}")

    simulation
  end

end
