unless Rails.env.test?
	ExperimentWatcher.watch_experiments

  # SiM monitoring threads are now started in Rakefile
	#InfrastructureFacadeFactory.start_all_monitoring_threads

  InfrastructureFacadeFactory.start_monitoring_thread_for('qsub')

end