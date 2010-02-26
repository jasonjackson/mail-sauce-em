class Injection
  include Nanite::Actor

  require File.dirname(__FILE__) + '/../../../lib/tenjin'
  require File.dirname(__FILE__) + '/../../../lib/tmail'
  require File.dirname(__FILE__) + '/../../../lib/redis-rb/lib/redis.rb'
  require 'rubygems'
  require 'net/smtp'
  require 'fileutils'

  expose :tests

  def tests(payload)

    @content_path = '/tmp/email_content'
    payload_array = Marshal.load(payload)
    content_hash = payload_array[0]
    envelope = payload_array[1]
    content_id  = "military-#{content_hash['listname']}-#{content_hash['timestamp']}"

    content_store = Redis.new :host => 'sfqload01.military.com', :port => '6379' 
    
    # Create the content directory on the local box if it doesn't exist
    unless File.exist?(@content_path)
      FileUtils.mkdir_p @content_path
    end

    # Local copy of the content file
    tmp_files = "#{@content_path}/#{content_hash['listname']}"

    # Is the local file there and newer than 6 hours old?
    if File.exist?("#{tmp_files}.html") && File.new("#{tmp_files}.html").mtime > Time.now - 21600
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


    engine = Tenjin::Engine.new

    envelope.each do |member|

      context = { :email => member['email'], :fname => member['fname'], :lname => member['lname'], :mailid => member['mailid'], :memberid => member['memberid'], :status => member['status'], :hash => generate_hash(member['email']) }

      # Render the content via the tenjin engine
      html_output = engine.render(html, context)
      txt_output = engine.render(txt, context)
      sub_output = engine.render(sub, context)

      email = TMail::Mail.new
      email.to = member['email']
      email.from = "Military.com <newsltr@miltnews.com>"
      email.subject = sub_output
      email.date = Time.now
      email.mime_version = '1.0'
      email['Return-Path'] = 'newsltr@miltnews.com'

      if txt_output
        part = TMail::Mail.new
        part.body = txt_output
        part.set_content_type 'text', 'plain', {'charset' => 'utf8'}
        part.transfer_encoding = '8bit'
        part.set_content_disposition "inline"
        email.parts << part
      end

      if html_output
        part = TMail::Mail.new
        part.body = html_output
        part.set_content_type 'text', 'html', {'charset' => 'utf8'}
        part.transfer_encoding = '8bit'
        part.set_content_disposition "inline"
        email.parts << part
      end

      email.set_content_type("multipart/alternative", nil, {"charset" => "utf8", "boundary" => ::TMail.new_boundary})
    
      # X-Headers 
      email['X-Campaignid'] = content_id

      msg = email.to_s

#      Net::SMTP.start('172.30.3.120', 25) do |smtp|
      Net::SMTP.start('10.33.99.196', 25) do |smtp|
        smtp.send_message msg, "Military.com <newsltr\@miltnews.com>", member['email']
      end
    end
    puts "success"
  end

  def write_io(path,io)
    File.open(path, 'w') { |f| f.write(io) }
  end

  def generate_hash(email)
    seed = 'Ti8IWoYU7edItg8TM6Dz6Wt1p6c='
    hash = Digest::MD5.hexdigest("#{email.downcase}#{seed}")
    return hash
  end

end


