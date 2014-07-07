# Binds Scalarm user, experiment and cloud virtual machine instance
# providing static information about VM (set once)
#
# Attributes (besides of generic SimulationManagerRecord's)
# - cloud_name => string - name of the cloud, e.g. 'pl_cloud', 'amazon'
# - image_secrets_id => id of CloudImageSecrets
# - vm_id => string - instance id of the vm
# - pid => integer - PID of SimulationManager application (if executed)
# - instance_type => string - name of instance type
#
# - public_host => public hostname of machine which redirects to ssh port
# - public_ssh_port => port of public machine redirecting to ssh private port

require 'infrastructure_facades/infrastructure_errors'

class CloudVmRecord < MongoActiveRecord
  include SimulationManagerRecord
  include SSHEnabledRecord

  SSH_AUTH_METHODS = %w(password)

  def resource_id
    self.vm_id
  end

  def self.collection_name
    'vm_records'
  end

  def image_secrets
    @image_secrets ||= CloudImageSecrets.find_by_id(image_secrets_id)
  end

  def experiment
    @experiment ||= Experiment.find_by_id(experiment_id)
  end

  def cloud_secrets
    @cloud_secrets ||= CloudSecrets.find_by_query(cloud_name: cloud_name, user_id: user_id)
  end

  # additional info for specific cloud should be provided by CloudClient
  def to_s
    "Id: #{vm_id}, Launched at: #{created_at}, Time limit: #{time_limit}, "
    "SSH address: #{public_host}:#{public_ssh_port}"
  end

  def ssh_params
    {
        port: public_ssh_port, password: image_secrets.secret_image_password,
        auth_methods: SSH_AUTH_METHODS, paranoid: false, user_known_hosts_file: %w(/dev/null),
        timeout: 30
    }
  end

  def has_ssh_address?
    (not self.public_host.blank?) and (not self.public_ssh_port.blank?)
  end

  def update_ssh_address!(vm_instance)
    psa = vm_instance.public_ssh_address
    self.public_host, self.public_ssh_port = psa[:host], psa[:port]
    self.save
  end

  def log_path
    "/tmp/log_sm_#{sm_uuid}"
  end

  def monitoring_group
    self.image_secrets_id
  end

  def validate
    raise InfrastructureErrors::NoCredentialsError if image_secrets_id.nil?
    raise InfrastructureErrors::InvalidCredentialsError if image_secrets.invalid
  end

  def has_usable_cloud_secrets?
    # TODO: this is hack - should be delegated to cloud clients,
    # TODO: but cloud clients are considered to work only on Cloud-API level
    if cloud_name == 'pl_cloud'
      cloud_secrets and cloud_secrets.login and
          (has_usable_proxy? or has_valid_password?)
    else
      true
    end
  end

  def has_usable_proxy?
    cloud_secrets.secret_proxy
  end

  def has_valid_password?
    not cloud_secrets.invalid and cloud_secrets.secret_password
  end

  private # --------

  def _get_ssh_session
    Net::SSH.start(public_host, image_secrets.image_login, ssh_params)
  end

  def _get_scp_session
    Net::SCP.start(public_host, image_secrets.image_login, ssh_params)
  end

end