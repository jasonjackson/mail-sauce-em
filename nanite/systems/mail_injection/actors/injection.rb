class Injection
  include Nanite::Actor

  require File.dirname(__FILE__) + '/../../../lib/tenjin'
  require File.dirname(__FILE__) + '/../../../lib/mailfactory/lib/mailfactory'
  require File.dirname(__FILE__) + '/../../../lib/redis-rb/lib/redis.rb'
  require File.dirname(__FILE__) + '/../../../lib/deferrable_pool.rb'
  require 'rubygems'
  require 'net/smtp'
  require 'fileutils'

  expose :mailer

  def mailer(payload)

    @content_path = '/tmp/email_content'
    payload_array = Marshal.load(payload)
    content_hash = payload_array[0]
    envelope = payload_array[1]
    content_id  = "monster-#{content_hash['listname']}-#{content_hash['timestamp']}"

    content_store = Redis.new :host => 'sfqload01.monster.com', :port => '6379' 
    
    # Create the content directory on the local box if it doesn't exist
    unless File.exist?(@content_path)
      FileUtils.mkdir_p @content_path
    end

    # Local copy of the content file
    tmp_files = "#{@content_path}/#{content_hash['listname']}"

    # Is the local file there and newer than 24 hours old?  If not pull from redis.
    if File.exist?("#{tmp_files}.html") && File.new("#{tmp_files}.html").mtime > Time.now - 86400
      html = "#{tmp_files}.html"
      html_cache = "#{tmp_files}.html.cache"
      sub = "#{tmp_files}.sub"
      sub_cache = "#{tmp_files}.sub.cache"
      txt = "#{tmp_files}.txt"
      txt_cache = "#{tmp_files}.txt.cache" 
    else
      FileUtils.rm_r Dir.glob("#{tmp_files}.*"), :force => true    
      write_io("#{tmp_files}.html", content_store["#{content_hash['listname']}-html"])
      write_io("#{tmp_files}.html.cache", content_store["#{content_hash['listname']}-chtml"])
      write_io("#{tmp_files}.sub", content_store["#{content_hash['listname']}-sub"])
      write_io("#{tmp_files}.sub.cache", content_store["#{content_hash['listname']}-csub"])
      write_io("#{tmp_files}.txt", content_store["#{content_hash['listname']}-txt"])
      write_io("#{tmp_files}.txt.cache", content_store["#{content_hash['listname']}-ctxt"])
      html = "#{tmp_files}.html"
      html_cache = "#{tmp_files}.html.cache"
      sub = "#{tmp_files}.sub"
      sub_cache = "#{tmp_files}.sub.cache"
      txt = "#{tmp_files}.txt"
      txt_cache = "#{tmp_files}.txt.cache"
    end


    jobs = envelope.map do |member|

      context = { :email => member['email'], :fname => member['fname'], :lname => member['lname'], :mailid => member['mailid'], :memberid => member['memberid'], :status => member['status'], :hash => generate_hash(member['email']) }

      # Render the content via the tenjin engine
      engine = Tenjin::Engine.new
      html_output = engine.render(html, context)
      txt_output = engine.render(txt, context)
      sub_output = engine.render(sub, context)

      mail = MailFactory.new
      mail.to = member['email']
      email.from = "Monster.com <updates@monster.com>"
      mail.subject = sub_output ? sub_output : "Subject content not found."
      mail.text = txt_output ? txt_output : "TXT content not found."
      mail.html = html_output ? html_output : "HTML content not found."

      lambda {
        deferrable = EM::P::SmtpClient.send(
          :host=>'10.33.99.196',
          :port=>25,
          :domain=>"monster.com",
          :from=>mail.from,
          :to=>mail.to,
          :content=>"#{mail.to_s}\r\n.\r\n"
        )
      deferrable.callback { puts 'deferrable callback triggered!' }
      deferrable # but you must return the deferrable from the proc
      }
    end


    num_active_conns = 200

    pool = DeferrablePool.new(num_active_conns, jobs)
    pool.on_callback { puts 'single mail complete' }
    pool.on_errback { puts 'single mail errored' }
    pool.callback { puts 'all mail sent' }

    puts "success"
  end

  def write_io(path,io)
    File.open(path, 'w') { |f| f.write(io) }
  end

  def generate_hash(email)
    seed = 'XissssYc7wdgtg8fM6Dr6rt1p5a='
    hash = Digest::MD5.hexdigest("#{email.downcase}#{seed}")
    return hash
  end

end


