class CustomPointsExperiment < Experiment
  # parameter_ids: Array of String parameter ids
  def init_empty(simulation)
    self.doe_info = [ [ 'csv_import', simulation.input_parameters.keys, [] ] ]
    self.experiment_input = Experiment.prepare_experiment_input(simulation, {}, self.doe_info)
    self.type = 'manual_points'
    self.cached_value_list = [[]]
    self.size = 0
  end

  def self.from_experiment(experiment)
    self.new(experiment.attributes)
  end

  # Add a parameter space point by creating a simulation run
  # @return [Fixnum] index of created simulation run
  def add_point!(point)
    add_points!([point]).first
  end

  # @return [Array<Fixnum>] indexes of created simulation run
  def add_points!(points)
    begin
      points.map {|p| self._add_single_point(p)}
    ensure
      extend_progress_bar(true)
      save
    end
  end

  def self.where(cond, opts = {})
    super({type: 'manual_points'}.merge(cond), opts)
  end

  def _add_single_point(point)
    case point
      when Hash then _add_single_point_hash(point)
      when Array then _add_single_point_tuple(point)
      else raise ArgumentError("Argument neither Hash nor Array: #{point}")
    end
  end

  # Example point:
  # {'param-1' => 1, 'param-2' => 20.0}
  # @return [Fixnum] new size of an experiment which is an index of new simulation_run
  def _add_single_point_hash(point)
    _add_single_point_tuple(single_point_hash_to_tuple(point))
  end

  # Point is a tuple of values of parameters in order of parameter_ids
  # Point should be valid.. otherwise there will be nasty error
  # @return [Fixnum] new size of an experiment which is an index of new simulation_run
  def _add_single_point_tuple(point)
    begin
      old_pids = self.doe_info[0][2]
      old_cvals = self.cached_value_list[0]
      old_size = self.size

      self.doe_info[0][2] << point
      self.cached_value_list[0] << point
      self.size += 1

    rescue => e
      Rails.logger.error("Error occurred during _add_single_point_tuple: #{e}")
      self.doe_info[0][2] = old_pids
      self.cached_value_list[0] = old_cvals
      self.size = old_size
      raise
    end
  end

  def single_point_hash_to_tuple(point)
    csv_parameter_ids.collect do |pid|
      point[pid.to_s] or point[pid.to_sym]
    end
  end

  # If experiment is not empty (uninitialized with points yet), are all scheduled simulation points done?
  def completed?
    if self.experiment_size == 0
      false
    else
      super
    end
  end
end
