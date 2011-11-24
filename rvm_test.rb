# Load requirements
#
# RubyGems
require 'rubygems'

# Require pry for debugging
require 'pry'
require 'pry-doc'

# Commandline options parser
require 'clint'

# Require session gem for shelled commands
require 'session'

# Require Pretty Print
require 'pp'

# ActiveRecord since models are AR backed
require 'active_record'
require 'active_support'

# Load YAML support
require 'yaml'

# Benchmarking for TestReports
require 'benchmark'
include Benchmark

# Define the APP_ROOT usign this file since its the startup file
APP_ROOT = File.dirname(__FILE__)

# Now, connect to the database using ActiveRecord
ActiveRecord::Base.establish_connection(YAML.load_file("#{APP_ROOT}/config/database.yml"))

# Now load the Model(s).
Dir[ "#{APP_ROOT}/app/models/*.rb"].each do |filename|
  # "#{filename}" == filename.to_s == filename - so just call filename
  load filename
end


# Currently, we are using marshalling to reload data to populate the report object.
@test_report = TestReport.new
@test_report.save


# Create a commandline parser object
cmdline = Clint.new


# Define the general usage message
cmdline.usage do
  $stderr.puts "Usage: #{File.basename(__FILE__)} [-h|--help]  ['rvm command_to_run'] [-s|--script rvm_test_script]"
end


# Define the help message
cmdline.help do
  $stderr.puts "  -h, --help\tshow this help message"
  $stderr.puts "Note: RVM commandsets not in a scriptfile must be surrounded by '' - e.g. #{File.basename(__FILE__)} 'rvm info'"
end


# Define the potential options
cmdline.options :help => false, :h => :help
cmdline.options :script => false, :s => :script
cmdline.options :marshal => false, :m => :marshal

# Parse the actual commandline arguments
cmdline.parse ARGV


# If the command options is for help, usage, or there are no arguments
# then display the help message and abort.
if cmdline.options[:help] || ARGV[0] == nil
  cmdline.help
  abort
elsif cmdline.options[:script]
    # PROCESS BATCH FILE - Open a bash session first. Will be passed in for use.
    # Open the script and parse. Should something go wrong with the file handler
    # display the help and abort. Wrap in a begin/rescue to handle it gracefully.
    # This executes each line storing that command's returned data in the database.
      begin
        # We call ARGV[0] here rather than ARGV[1] because the original ARGV[0] was
        # --script (or -s). when cmdline.options[:script] gets processed, it gets
        # dumped and the remaining argument(s) are shifted down in the ARGV array.
        # So now the script name is ARGV[0] rather than the normal ARGV[1]
        # We'll have to do this over and over as we keep processing deeper in the
        # options parsing if there were more options allowed / left.        
        # Open a shell session.
        @bash = Session::Bash.new
        
        # Capture the initial environment before any commands are run.
        puts 'Captured Test Report Initial Environment - #{TestReport.env_initial}'
        @test_report.env_initial = @bash.execute "/usr/bin/printenv"
        @test_report.env_initial = @test_report.env_to_hash(@test_report.env_initial[0])
        
          # Now we process the individual commands
          File.foreach(ARGV[0]) do |cmd|
            cmd.strip!
            next if cmd =~ /^#/ or cmd.empty?
            
            # We want to parse specific expectations so we can manage logic flow based on that match
            # Check for #cmd:start()= / #cmd:stop= - anything between deliniates actual execution output
            # TODO - Ask mpapis to use this to add his comment testing
            if cmd =~ /#cmd:start(.*)=$/ then
              puts "\n CMD PARSING: Parsed cmd:start()= string\n"
            else
              if cmd =~ /^#cmd:stop=$/
                puts "\n CMD PARSING: Parsed cmd:stop= string\n"
              end 
            end
            
            # TODO - Need to define a method to manage the parsing within TestReport such that we can
            # TODO - assert specifics regarding expectations. The entry point for using the method is the top
            # TODO - of @test_report.run-command.
            
            # We've done our checking, execute.
            @test_report.run_command( cmd, @test_report, @bash)
          end
        puts "TEST REPORT - Exit Status: #{@test_report.exit_status = @bash.status}"
            
      rescue Errno::ENOENT => e
          # The file wasn't found so display the help and abort.
          cmdline.help
          abort
      end
        # BATCH HAS BEEN PROCESSED
        # Now that all the commands in the batch have been processed and added to test_report,
        # now is when to save the Test Report, immediately following the processing of all commands.
        @test_report.save!
        
        @test_report.display_combined_gist_report
        @test_report.dump_obj_store(@test_report)
            

elsif cmdline.options[:marshal]
      # Sessioned - encapsulated within load_and_replay_obj_store
      puts "Loading and Re-executing previous session"
      @test_report.load_and_replay_obj_store(@test_report)
      puts "Repeat execution of previous session complete!\n"
else
  # PROCESS SINGLE COMMAND - Meant for one-off commands play.
  # Not that its wrong, maybe a bit of a waste of resources, but sessioning had to be added due to how we rely on
  # run commands through the structure. Oh, well. All is good so onwards and upwards! This handles when just a single command,
  # not a script, is passed. Since its not a script, ARGV[0] should be the command to be run encased in ''.
  bash = Session::Bash.new
  @test_report.run_command(ARGV[0].strip, @test_report, bash)
  @test_report.save!
   
  @test_report.display_short_report

end
