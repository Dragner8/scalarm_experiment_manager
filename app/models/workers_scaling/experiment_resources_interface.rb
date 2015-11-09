require 'infrastructure_facades/infrastructure_facade_factory'
require 'infrastructure_facades/infrastructure_errors'
require 'workers_scaling/utils/query'
include InfrastructureErrors
module WorkersScaling
  ##
  # Experiment interface to schedule and maintain computational resources
  class ExperimentResourcesInterface

    ##
    # Params:
    # * experiment
    # * user_id
    # * allowed_infrastructures
    #     Variable storing user-defined workers limits for each infrastructure
    #     Only infrastructures specified here can be used by experiment.
    #     Format: [{infrastructure: <infrastructure>, limit: <limit>}, ...]
    #     <infrastructure> - hash with infrastructure info
    #     <limit> - integer
    def initialize(experiment, user_id, allowed_infrastructures)
      @experiment = experiment
      @user_id = BSON::ObjectId(user_id.to_s)
      @facades_cache = {}
      @allowed_infrastructures = allowed_infrastructures
    end

    ##
    # Returns list of available infrastructure configurations for experiment
    # Infrastructure configuration format: {name: <name>, params: {<params>}}
    # <params> may include e.g. credentials_id for private_machine
    def get_available_infrastructures
      InfrastructureFacadeFactory.list_infrastructures(@user_id)
          .flat_map {|x| x.has_key?(:children) ? x[:children] : x }
          .select {|x| x[:enabled]}
          .map {|x| x[:infrastructure_name].to_sym}
          .flat_map do |infrastructure_name|
            InfrastructureFacadeFactory.get_facade_for(infrastructure_name).get_subinfrastructures(@user_id)
          end
          .select {|x| !!@allowed_infrastructures.detect {|ai| infrastructures_equal?(x, ai[:infrastructure])}}
      # TODO return allowed infrastructures filter by available
    end

    ##
    # Returns amount of Workers that can be yet scheduled on given infrastructure
    def current_infrastructure_limit(infrastructure)
      infrastructure_limit = @allowed_infrastructures.detect do |entry|
        infrastructures_equal?(infrastructure, entry[:infrastructure])
      end
      if infrastructure_limit.nil?
        0
      else
        [0, infrastructure_limit[:limit] - get_workers_records_count(infrastructure,
          cond: Query::LIMITED_WORKERS)].max
      end
    end

    ##
    # Schedules given amount of workers onto infrastructure and returns theirs sm_uuids
    # Additional params will be passed to start_simulation_managers facade method.
    # Raises InfrastructureError
    # Number of workers scheduled may be lesser than <amount>,
    # if limit left or number of simulations left to send is lesser than <amount>
    def schedule_workers(amount, infrastructure, params = {})
      begin
        @experiment.reload
        starting_workers = get_workers_records_list(infrastructure, cond: Query::STARTING_WORKERS).map &:sm_uuid
        initializing_workers = get_workers_records_list(infrastructure, cond: Query::INITIALIZING_WORKERS).map &:sm_uuid
        _, sent, done = @experiment.get_statistics

        # initializing workers have not yet taken simulations, need to avoid scheduling workers that will not get one
        simulations_left = @experiment.experiment_size - (sent + done) - initializing_workers.count

        # amount includes workers that do not count towards throughput yet, algorithm has no knowledge about them
        amount -= starting_workers.count + initializing_workers.count

        amount = [amount, current_infrastructure_limit(infrastructure), simulations_left].min
        return starting_workers + initializing_workers if amount <= 0

        # TODO: time of experiment
        params[:time_limit] = 60 if params[:time_limit].nil?
        params.merge! infrastructure[:params]

        # TODO: SCAL-1024 - facades use both string and symbol keys
        params.symbolize_keys!.merge!(params.stringify_keys)
        get_facade_for(infrastructure[:name])
          .start_simulation_managers(@user_id, amount, @experiment.id.to_s, params)
          .map(&:sm_uuid)
          .concat(starting_workers + initializing_workers)
      rescue InvalidCredentialsError, NoCredentialsError
        # TODO inform user about credentials error
        raise
      end
    end

    ##
    # Marks worker with given sm_uuid to be deleted after finishing given number of simulations
    # If overwrite is set to false, worker will not be marked if simulations_left field is already set,
    # otherwise new number will be set in all cases
    # Using overwrite=true may result in unintentional resetting simulations_left field,
    # effectively prolonging lifetime of worker, therefore default value is false
    def limit_worker_simulations(sm_uuid, simulations_left, overwrite=false)
      worker = get_worker_record_by_sm_uuid(sm_uuid)
      unless worker.nil?
        worker.simulations_left = simulations_left if worker.simulations_left.blank? or overwrite
        worker.save
      end
    end

    ##
    # Simplifies use of #limit_worker_simulations when the goal is to stop worker
    # Provides more intuitive name
    def soft_stop_worker(sm_uuid)
      limit_worker_simulations(sm_uuid, 1)
    end

    ##
    # Returns list of workers records for infrastructure
    def get_workers_records_list(infrastructure, params = {})
      get_workers_records_cursor(infrastructure, params).to_a
    end

    ##
    # Returns workers records count for infrastructure
    def get_workers_records_count(infrastructure, params = {})
      get_workers_records_cursor(infrastructure, params).count
    end

    ##
    # Returns overall Workers count for Experiment matching given params
    def count_all_workers(params = {})
      get_available_infrastructures
          .flat_map { |infrastructure| get_workers_records_count(infrastructure, params) }
          .reduce(0) { |sum, count| sum + count }
    end

    ##
    # Returns worker record for given sm_uuid
    def get_worker_record_by_sm_uuid(sm_uuid)
      get_available_infrastructures.flat_map do |infrastructure|
        get_workers_records_cursor(infrastructure, cond: {sm_uuid: sm_uuid}).first
      end .first
    end

    ##
    # Yields workers for given records
    # Usage:
    #   yield_workers(records) do |worker|
    #      worker.<some method>
    #   end
    # Workers commands: restart, stop, destroy_record
    def yield_workers(records)
      records.each do |record|
        get_facade_for(record.infrastructure).yield_simulation_manager(record) {|worker| yield worker}
      end
    end

    private

    ##
    # Compares infrastructure description from #get_available_infrastructures with @allowed_infrastructures entry.
    # Entry from @allowed_infrastructures may have additional fields that
    # should not be taken into consideration in comparison.
    # Return true when infrastructures are equal, false otherwise.
    def infrastructures_equal?(from_available, from_allowed)
      # TODO replace with infrastructure id
      return false if from_allowed[:name] != from_available[:name]
      from_available[:params].each do |key, value|
        return false if from_allowed[:params][key] != value
      end
      true
    end

    ##
    # Returns InfrastructureFacade for given infrastructure name
    # Previously accessed facades are cached
    def get_facade_for(infrastructure_name)
      unless @facades_cache.has_key? infrastructure_name
        throw NoSuchInfrastructureError unless get_available_infrastructures.map {|infrastructure| infrastructure[:name]}
                                                                            .include? infrastructure_name
        @facades_cache[infrastructure_name] = InfrastructureFacadeFactory.get_facade_for infrastructure_name
      end
      @facades_cache[infrastructure_name]
    end

    ##
    # Returns Mongo cursor for given query
    # Arguments:
    # * infrastructure - hash with infrastructure info
    # * params:
    #   * opts
    #   * cond
    # Possible cond and opts can be found in MongoActiveRecord#where.
    def get_workers_records_cursor(infrastructure, params = {})
      cond = {experiment_id: @experiment.id.to_s, user_id: @user_id}
      cond.merge! params[:cond] if params.has_key? :cond
      cond.merge! infrastructure[:params]
      opts = {}
      opts.merge! params[:opts] if params.has_key? :opts

      get_facade_for(infrastructure[:name]).sm_record_class.where(cond, opts)
    end
  end

end
