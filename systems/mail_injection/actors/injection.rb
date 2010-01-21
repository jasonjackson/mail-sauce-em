class Injection
  include Nanite::Actor

  require File.dirname(__FILE__) + '/../../../lib/tenjin'
  require File.dirname(__FILE__) + '/../../../lib/tmail'
  require File.dirname(__FILE__) + '/../../../lib/redis-rb/lib/redis.rb'
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
    
    if File.exist?(@content_path)
      write_io("#{@content_path}/#{content_hash['listname']}.html", content_store["#{content_hash['listname']}-html"])
      write_io("#{@content_path}/#{content_hash['listname']}.html.cache", content_store["#{content_hash['listname']}-chtml"])
      write_io("#{@content_path}/#{content_hash['listname']}.sub", content_store["#{content_hash['listname']}-sub"])
      write_io("#{@content_path}/#{content_hash['listname']}.sub.cache", content_store["#{content_hash['listname']}-csub"])
      write_io("#{@content_path}/#{content_hash['listname']}.txt", content_store["#{content_hash['listname']}-txt"])
      write_io("#{@content_path}/#{content_hash['listname']}.txt.cache", content_store["#{content_hash['listname']}-ctxt"])
    else
      FileUtils.mkdir_p @content_path
      write_io("#{@content_path}/#{content_hash['listname']}.html", content_store["#{content_hash['listname']}-html"])
      write_io("#{@content_path}/#{content_hash['listname']}.html.cache", content_store["#{content_hash['listname']}-chtml"])
      write_io("#{@content_path}/#{content_hash['listname']}.sub", content_store["#{content_hash['listname']}-sub"])
      write_io("#{@content_path}/#{content_hash['listname']}.sub.cache", content_store["#{content_hash['listname']}-csub"])
      write_io("#{@content_path}/#{content_hash['listname']}.txt", content_store["#{content_hash['listname']}-txt"])
      write_io("#{@content_path}/#{content_hash['listname']}.txt.cache", content_store["#{content_hash['listname']}-ctxt"])
    end

    engine = Tenjin::Engine.new

    envelope.each do |member|

      context = { :email => member['email'], :fname => member['fname'], :lname => member['lname'], :mailid => member['mailid'], :memberid => member['memberid'], :status => member['status'], :hash => generate_hash(member['email']) }

      html_output = engine.render("#{@content_path}/#{content_hash['listname']}.html", context)
      txt_output = engine.render("#{@content_path}/#{content_hash['listname']}.txt", context)
      sub_output = engine.render("#{@content_path}/#{content_hash['listname']}.sub", context)

      email = TMail::Mail.new
      email.to = member['email']
      email.from = "Monster.com <newsltr@monster.com>"
      email.subject = sub_output
      email.date = Time.now
      email.mime_version = '1.0'
      email['Return-Path'] = 'newsltr@monster.com'

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

      Net::SMTP.start('10.33.99.196', 25) do |smtp|
        smtp.send_message msg, "Monster.com <newsltr\@monster.com>", member['email']
      end
    end
    puts "success"
  end

  def write_io(path,io)
    File.open(path, 'w') { |f| f.write(io) }
  end

  def generate_hash(email)
    seed = 'Ti8IWoYt7ed5tg8TM6Dz6Wt1p6c='
    hash = Digest::MD5.hexdigest("#{email.downcase}#{seed}")
    return hash
  end

end


