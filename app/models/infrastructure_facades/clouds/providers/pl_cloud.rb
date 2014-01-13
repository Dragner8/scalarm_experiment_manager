require 'infrastructure_facades/clouds/abstract_cloud_client'
require 'infrastructure_facades/pl_cloud_utils/pl_cloud_util'
require 'infrastructure_facades/pl_cloud_utils/pl_cloud_util_instance'

module PLCloud

  class CloudClient < AbstractCloudClient
    def initialize(secrets)
      super(secrets)
      @plc_util = PLCloudUtil.new(secrets)
    end

    def self.short_name
      'pl_cloud'
    end

    def self.full_name
      'PLGrid Cloud'
    end

    def all_vm_ids
      @plc_util.all_vm_info.keys.map {|i| i.to_i}
    end

    # TODO: return value is vm_instance, think about ids
    def create_instances(base_name, image_id, number, params)
      @plc_util.create_instances(base_name, image_id, number).map do |vm_id|
        vm_instance(vm_id)
      end
    end

    ## -- VM instance methods --

    # TODO: VM name is constant, consider using vm_record
    def name(id)
      @plc_util.vm_info(id)['NAME']
    end

    # TODO
    STATES_MAPPING = {
        'INIT'=> :initializing,
        'PENDING'=> :initializing,
        'HOLD'=> :error,
        'ACTIVE'=> :running,
        'STOPPED'=> :deactivated,
        'SUSPENDED'=> :deactivated,
        'DONE'=> :deactivated,
        'FAILED'=> :error,
        'POWEROFF'=> :deactivated,
        'UNDEPLOYED'=> :deactivated
    }

    def status(id)
      STATES_MAPPING[
        PLCloudUtilInstance::VM_STATES[@plc_util.vm_info(id)['STATE'].to_i]
      ]
    end

    def exists?(id)
      @plc_util.all_vm_info.has_key? id
    end

    def terminate(id)
      @plc_util.delete_instance(id)
    end

    # @return [Hash] {:ip => string cloud public ip, :port => string redirected port} or nil on error
    def public_ssh_address(id)
      # String: public host of VM -- dynamically gets hostname from API
      vmi = @plc_util.vm_instance(id)
      vmi.redirections[22] or vmi.redirect_port(22)
    end

  end

end