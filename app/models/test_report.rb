class TestReport < ActiveRecord::Base
  
  # Github API interface
  require 'github_api'

  # Now create both a Github and a Report object
  #
  
  # You define it such as follows for a Github object
  # There are other types like :oauth2, :login, etc. We just chose :basic_auth for now. See http://developer.github.com/v3/
  # eg. @github = Github.new(:basic_auth => "username/token:<api_key>", :repo => "repo_name")
  # @github = Github.new(:basic_auth => "deryldoucette/token:cc32f016a438fe3526be017f68e5e7b5", :repo => 'rvm-test')
  # We log in via the TestReport github call because it should be the TestReport that spawns the connection, not Command.
  # ISSUE: We need to instantiate the TestReport object first in order to gain access to the method/action.
  #
  # So its not in the repository, we put the bash_auth string into config/github.rb file and load it in a variable
  # This gives us @login_string to be used later.
  load "#{APP_ROOT}/config/github.rb"
  
  # has_and_belongs_to_many :commands, :join_table => "test_reports_commands"
  attr_accessor :github
  
  has_many :commands
  
  accepts_nested_attributes_for :commands, :allow_destroy => true, :reject_if => proc { |attributes| attributes['cmd'].blank? }
  
  def self.initialize
    @github = self.github(@login_string)  
  end
        
  def record_timings(&cmds)
    Benchmark.benchmark(CAPTION) do |x|
      x.report("Timings: ", &cmds)
    end
        
  end

  def github(login_string)
    return Github.new(:login => "#{login_string[:login]}", :user => "#{login_string[:user]}", :password => "#{login_string[:password]}", :repo => "#{login_string[:repo]}")    
  end
  
  def env_to_hash(env_string)
    lines = env_string.split("\n")
    key_value_pairs = lines.map { |line|
      key, value = *line.split("=", 2)
      [key.to_sym, value]
    }

    Hash[key_value_pairs]
        
    
  end

  def run_command( cmd, bash )
    command = commands.build    
    command.run( cmd, bash )
    command.save
    self.sysname = command.sysname
        
    
  end
  
  def display_combined_gist_report
    self.report = self.display_short_report()
    self.gist_url = "#{@github.gists.create_gist(:description => "Complete Report", :public => true, :files => { "console.sh" => { :content => report.presence || "Cmd had no output" }}).html_url}"
    puts "The Complete report URL is: #{self.gist_url} - Report Exit Status: #{self.exit_status}" 
        
    
  end
  
  def display_short_report
    self.commands.each do |command|
      puts "Test Report for: #{command.test_report_id}" + " - Test Node: #{command.sysname} - " + "Cmd ID: " + command.id.to_s + " - Executed: \"#{command.cmd.to_s}\"" + " at " +  "#{command.updated_at.to_s}" + " Gist URL: #{command.gist_url}" + " Cmd exit code: #{command.exit_status}"
    end
  end
  
  def dump_obj_store
    File.open('db/testreport_marshalled.rvm', 'w+') do |report_obj|
      puts "\nDumping TestReport object store"
      Marshal.dump(self, report_obj)
    end
    puts "Dumping Command object store\n"
    self.commands.each do |cmd|
      cmd.dump_obj_store
    end
  end
  
  def load_and_replay_obj_store
    @bash = Session::Bash.new
    
    File.open'db/testreport_marshalled.rvm' do |report_obj|
      puts "\nLoading TestReport object store\n"
      @test_report = Marshal.load(report_obj)
    end
    
    puts "Loaded TestReport ID is: " "#{@test_report.id}"    
    puts "Replaying commands "
    @test_report.commands.each do |cmd, bash|
      cmd.run cmd.cmd, @bash
    end
    
    # Recreate a gisted report of this new run based off the marshalled object(s)
    @test_report.display_combined_gist_report
    puts "\nExiting load_obj_store\n"
  end
  
  def open_session

  end
  
end
