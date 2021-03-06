class Redis
  class Pipeline < Redis
    BUFFER_SIZE = 50_000 unless defined? BUFFER_SIZE
    
    def initialize(redis)
      @redis = redis
      @commands = []
    end
   
    def call_command(command)
      @commands << command
    end

    def execute
      return if @commands.empty?
      @redis.call_command(@commands)
      @commands.clear
    end

  end
end
