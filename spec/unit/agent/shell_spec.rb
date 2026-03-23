require 'spec_helper'

module MCollective
  module Agent
    describe Shell do
      let(:agent_file) { File.join('files', 'mcollective', 'agent', 'shell.rb')}
      let(:agent) { MCollective::Test::LocalAgentTest.new('shell', :agent_file => agent_file).plugin }

      describe '#run' do
        it 'should delegate to #run_command' do
          agent.expects(:run_command).with(instance_of(MCollective::RPC::Request)).returns({
            :exitcode => 0,
            :stdout => "foo\n",
            :stderr => '',
          })
          result = agent.call(:run, :command => 'echo foo')
          result.should be_successful
        end
      end

      describe '#statuses' do
        let(:reply) { {} }

        before :each do
          agent.stubs(:reply).returns(reply)
          @tmpdir = Dir.mktmpdir
          Shell::Job.stubs(:state_path).returns(@tmpdir)
        end

        after :each do
          FileUtils.remove_entry_secure @tmpdir
        end

        it 'should return stdout, stderr, and exitcode for stopped jobs' do
          job = Shell::Job.new
          job.start_command('echo foo')
          job.wait_for_process

          agent.call(:statuses, :handles => [job.handle])
          statuses = reply[:statuses]
          statuses.should have_key(job.handle)
          statuses[job.handle][:status].should == :stopped
          statuses[job.handle][:stdout].should == "foo\n"
          statuses[job.handle][:stderr].should == ''
          statuses[job.handle][:exitcode].should == 0
        end

        it 'should return stdout and stderr for running jobs' do
          job = Shell::Job.new
          job.start_command(%{ruby -e 'STDOUT.sync = true; puts "partial"; sleep 60'})
          sleep 0.5

          agent.call(:statuses, :handles => [job.handle])
          statuses = reply[:statuses]
          statuses[job.handle][:status].should == :running
          statuses[job.handle][:stdout].should == "partial\n"
          statuses[job.handle][:stderr].should == ''
          statuses[job.handle].should_not have_key(:exitcode)

          job.kill
          job.wait_for_process
        end

        it 'should return error for invalid handle without affecting valid handles' do
          job = Shell::Job.new
          job.start_command('echo good')
          job.wait_for_process

          agent.call(:statuses, :handles => [job.handle, 'nonexistent-handle'])
          statuses = reply[:statuses]
          statuses[job.handle][:status].should == :stopped
          statuses[job.handle][:stdout].should == "good\n"
          statuses['nonexistent-handle'][:status].should == :error
          statuses['nonexistent-handle'].should have_key(:error)
        end

        it 'should handle multiple handles in one call' do
          job_one = Shell::Job.new
          job_one.start_command('echo one')
          job_one.wait_for_process

          job_two = Shell::Job.new
          job_two.start_command('echo two')
          job_two.wait_for_process

          agent.call(:statuses, :handles => [job_one.handle, job_two.handle])
          statuses = reply[:statuses]
          statuses.keys.size.should == 2
          statuses[job_one.handle][:stdout].should == "one\n"
          statuses[job_two.handle][:stdout].should == "two\n"
        end
      end

      describe '#run_command' do
        let(:reply) { {} }

        before :each do
          agent.stubs(:reply).returns(reply)
          @tmpdir = Dir.mktmpdir
          Shell::Job.stubs(:state_path).returns(@tmpdir)
        end

        after :each do
          FileUtils.remove_entry_secure @tmpdir
        end

        it 'should run cleanly' do
          agent.send(:run_command, :command => 'echo foo')
          reply[:exitcode].should == 0
          reply[:stdout].should == "foo\n"
        end

        it 'should cope with large amounts of output' do
          agent.send(:run_command, :command => %{ruby -e '8000.times { puts "flirble wirble" }'})
          reply[:success].should == true
          reply[:exitcode].should == 0
          reply[:stdout].should == "flirble wirble\n" * 8000
        end

        it 'should cope with large amounts of output on both channels' do
          agent.send(:run_command, :command => %{ruby -e '8000.times { STDOUT.puts "flirble wirble"; STDERR.puts "flooble booble" }'})
          reply[:success].should == true
          reply[:exitcode].should == 0
          reply[:stdout].should == "flirble wirble\n" * 8000
          reply[:stderr].should == "flooble booble\n" * 8000
        end

        it 'raise on a non-existent command' do
          lambda {
            agent.send(:run_command, :command => 'i_really_should_not_exist')
          }.should raise_error(/No such file or directory - i_really_should_not_exist/)
        end

        context 'timeout' do
          it 'should not timeout commands that exit quickly enough' do
            agent.send(:run_command, {
              :command => %{ruby -e 'puts "started"; sleep 1; puts "finished"'},
              :timeout => 2.0,
            })
            reply[:success].should == true
            reply[:exitcode].should == 0
            reply[:stdout].should == "started\nfinished\n"
            reply[:stderr].should == ''
          end

          it 'should timeout long running commands' do
            start = Time.now()
            agent.send(:run_command, {
              :command => %{ruby -e 'STDOUT.sync = true; puts "started"; sleep 5; puts "finished"'},
              :timeout => 1.0,
            })
            elapsed = Time.now() - start
            elapsed.should <= 2
            reply[:success].should == false
            reply[:exitcode].should == nil
            reply[:stdout].should == "started\n"
            reply[:stderr].should == ''
          end
        end
      end
    end
  end
end
