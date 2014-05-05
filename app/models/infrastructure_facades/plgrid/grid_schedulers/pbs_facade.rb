class PBSFacade < PlGridSchedulerBase
  def self.long_name
    'PBS'
  end

  def self.short_name
    'qsub'
  end

  def long_name
    self.class.long_name
  end

  def short_name
    self.class.short_name
  end

  def prepare_job_files(sm_uuid)
    IO.write("/tmp/scalarm_job_#{sm_uuid}.sh", prepare_job_executable)
  end

  def send_job_files(sm_uuid, scp)
    scp.upload! "/tmp/scalarm_simulation_manager_#{sm_uuid}.zip", '.'
    scp.upload! "/tmp/scalarm_job_#{sm_uuid}.sh", '.'
  end

  def submit_job(ssh, job)
    ssh.exec!("chmod a+x scalarm_job_#{job.sm_uuid}.sh")
    #  schedule the job with qsub
    qsub_cmd = [
        'qsub',
        '-q', job.queue,
        "#{job.grant_id.blank? ? '' : "-A #{job.grant_id}"}",
        "#{job.nodes.blank? ? '' : "-l nodes=#{job.nodes}:ppn=#{job.ppn}"}",
        '-j oe', # mix stderr with stdout
        '-o', job.log_path # output log
    ]
    #Rails.logger.debug("QSUB cmd: #{qsub_cmd.join(' ')}")
    submit_job_output = ssh.exec!("echo \"sh scalarm_job_#{job.sm_uuid}.sh #{job.sm_uuid}\" | #{qsub_cmd.join(' ')}")
    Rails.logger.debug("Output lines: #{submit_job_output}")

    if submit_job_output != nil
      output_lines = submit_job_output.split("\n")

      output_lines.each do |line|
        # checking if the first element is integer -> it is the identifier we are looking for
        if line[0].to_i.to_s == line[0]
          job.job_id = line.strip
          return true
        end
      end
    end

    false
  end

  def pbs_state(ssh, job)
    state_output = ssh.exec!("qstat #{job.job_id}")
    state_output.split("\n").each do |line|
      if line.start_with?(job.job_id.split('.').first)
        info = line.split(' ')
        return info[4]

      elsif line.start_with?('qstat: Unknown Job Id')
        return 'U'
      end
    end
    # unknown
    'U'
  end

  def is_done(ssh, job)
    %w(C).include?(pbs_state(ssh, job))
  end

  def is_job_queued(ssh, job)
    %w(Q T W U).include?(pbs_state(ssh, job))
  end

  # States from man qstat:
  # C -  Job is completed after having run/
  # E -  Job is exiting after having run.
  # H -  Job is held.
  # Q -  job is queued, eligible to run or routed.
  # R -  job is running.
  # T -  job is being moved to new location.
  # W -  job is waiting for its execution time
  # (-a option) to be reached.
  # S -  (Unicos only) job is suspend.

  STATES_MAPPING = {
      'C'=>:deactivated,
      'E'=>:deactivated,
      'H'=>:running,
      'Q'=>:initializing,
      'R'=>:running,
      'T'=>:running,
      'W'=>:initializing,
      'S'=>:error,
      'U'=>:deactivated # probably it's not in queue
  }

  def status(ssh, job)
    STATES_MAPPING[pbs_state(ssh, job)] or :error
  end

  def cancel(ssh, job)
    ssh.exec!("qdel #{job.job_id}")
  end

  def restart(ssh, job)
    cancel(ssh, job)
    if submit_job(ssh, job)
      job.created_at = Time.now
      job.save
      true
    else
      false
    end
  end

  def get_log(ssh, job)
    output = ssh.exec! "tail -25 #{job.log_path}"
    ssh.exec! "rm #{job.log_path}"
    output
  end

end