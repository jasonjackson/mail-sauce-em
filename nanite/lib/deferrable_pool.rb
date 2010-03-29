class DeferrablePool < EM::DefaultDeferrable
  def initialize(size = 200, jobs = [])
    @size = size
    @jobs = jobs
    @running = 0
  end

  # Adds a job to the job list, and schedules if possible
  def job(*a, &b)
    @jobs << EM::Callback(*a, &b)
    schedule
  end

  def schedule
    while @running < @size && @jobs.size > 0
      puts "Jobs: #{@jobs.size}"
      puts "Running: #{@running.size}"
      puts "Size: #{@size.size}"
      @running += 1
      job = @jobs.shift
      EM.next_tick do
        deferrable = job.call
        deferrable.callback { |*a| job_callback(*a) }
        deferrable.errback { |*a| job_errback(*a) }
      end
    end
  end

  def on_callback(*a, &b)
    @job_callback = EM::Callback(*a, &b)
  end

  def on_errback(*a, &b)
    @job_errback = EM::Callback(*a, &b)
  end

  def job_callback(*a)
    complete_job
    @job_callback.call(*a) if @job_callback
    try_succeed
  end

  def job_errback(*a)
    complete_job
    @job_errback.call(*a) if @job_errback
    try_succeed
  end

  def complete_job
    # TODO consider dropping this into next_tick to allow some grace for
    # closes, etc
    @running -= 1
    schedule
  end

  def try_succeed
    succeed if @running == 0 && @jobs.empty?
  end
end
