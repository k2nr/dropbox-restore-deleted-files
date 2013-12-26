require 'dropbox_sdk'

APP_KEY = 'kdq35jzh5j4phek'
APP_SECRET = 'q76tfe53hqd4u6a'

def auth
  flow = DropboxOAuth2FlowNoRedirect.new(APP_KEY, APP_SECRET)
  authorize_url = flow.start()

  `open "#{authorize_url}"`

  puts '1. Go to: ' + authorize_url
  puts '2. Click "Allow" (you might have to log in first)'
  puts '3. Copy the authorization code'
  print 'Enter the authorization code here: '
  code = gets.strip

  access_token, user_id = flow.finish(code)
  DropboxClient.new(access_token)
end

def get_restore_from
  print "datetime to restore from(format: yyyy/mm/dd hh:MM:ss)[default: 24 hours ago]: "
  date_time_s = gets.strip
  if date_time_s.empty?
    Time.now - 3600 * 24
  else
    DateTime.parse(date_time_s).to_time
  end
end

def get_restore_path
  print "path to restore[default: /]: "
  dir = gets.strip
  dir = '/' if dir.empty?
  dir
end

def restore_dir_contents(cli, path, restore_from, recursive=true)
  metadata = cli.metadata(path, 25000, true, nil, nil, true)
  contents = metadata["contents"]
  contents.each do |c|
    if c["is_dir"]
      restore_dir_contents(cli, c["path"], restore_from, recursive) if recursive
    else
      restore_content(cli, c["path"], restore_from) if c["is_deleted"]
    end
  end
end

def restore_content(cli_, path, restore_from=Time.now - 3600*24)
  sleep 0.3
  Thread.new do
    restorer = lambda do
      cli = Marshal.load(Marshal.dump(cli_))
      revisions = cli.revisions(path)
      current = revisions[0]
      modified = DateTime.parse(current["modified"]).to_time
      if current["is_dir"]
        puts "WARN: #{path} is directory"
        return
      end

      if current["is_deleted"] && modified >= restore_from
        rev = revisions.select{|r| not r["is_deleted"]}[0]["rev"]
        puts "restoring #{path} to revision #{rev} ..."
        cli.restore(path, rev)
      end
    end

    success = false
    while !success do
      begin
        restorer.call
        success = true
      rescue => e
        p e
        puts "restore failed #{path}. Will retry 10 seconds later"
        sleep 10
      end
    end
  end
end

def start(dir, restore_from)
  print "Are you ready to start? [yes/no]:"
  if gets.strip == "yes"
    restore_dir_contents(@client, dir, restore_from)
  end
end

@client = auth()
puts "linked account:", @client.account_info().inspect

dir = get_restore_path
restore_from = get_restore_from

start(dir, restore_from)
Thread.list.each { |t| t.join if t.alive? && t != Thread.current }
