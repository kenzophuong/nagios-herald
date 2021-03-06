require 'minitest/autorun'

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', '..', 'lib')
require 'nagios-herald'
require 'nagios-herald/config'
require 'nagios-herald/executor'
require 'nagios-herald/formatters/base'

# Test Formatter::Base.
class TestFormatterCheckCpuIdle < MiniTest::Unit::TestCase

  # TODO: We need a similar set of tests for RECOVERY emails.
  # Initial setup before we execute tests
  def setup
    @options = {}
    @options[:message_type] = 'EMAIL'
    @options[:nagios_url] = "http://nagios.example.com"
    @options[:formatter_name] = 'check_cpu'
    env_file = File.join(File.dirname(__FILE__), '..', 'env_files', 'check_cpu_idle.CRITICAL')
    NagiosHerald::Executor.new.load_env_from_file(env_file) # load an env file for testing
    NagiosHerald::Executor.new.load_formatters
    NagiosHerald::Executor.new.load_messages
    formatter_class = NagiosHerald::Formatter.formatters[@options[:formatter_name]]
    @formatter = formatter_class.new(@options)
  end

  def teardown
    # make certain we don't leave tons of empty temp dirs behind
    @formatter.clean_sandbox
  end

  # Test that we have a new NagiosHerald::Formatter object.
  def test_new_formatter
    assert_instance_of NagiosHerald::Formatter::CheckCpu, @formatter
  end

  def test_add_content_basic
    @formatter.add_text('test_add_content', 'This is test text')
    assert_equal 'This is test text', @formatter.content[:text][:test_add_content]
    @formatter.add_html('test_add_content', '<b>This is test HTML</b>')
    assert_equal '<b>This is test HTML</b>', @formatter.content[:html][:test_add_content]
    @formatter.generate_subject
    assert_equal "PROBLEM Service web.example.com/CPU is CRITICAL", @formatter.content[:subject]
    attachment_name = "#{@formatter.sandbox}/cat.gif"
    @formatter.add_attachment(attachment_name)
    assert @formatter.content[:attachments].include?(attachment_name), "Failed to attach #{attachment_name} to content hash."
  end

  def test_action_url
    @formatter.action_url
    assert_equal "<b>Action URL</b>: http://runbook.example.com/disk_space_alerts.html<br><br>", @formatter.content[:html][:action_url]
    assert_equal "Action URL: http://runbook.example.com/disk_space_alerts.html\n\n", @formatter.content[:text][:action_url]
  end

  def test_host_info
    @formatter.host_info
    assert_equal "<br><b>Host</b>: web.example.com <b>Service</b>: CPU<br/><br>", @formatter.content[:html][:host_info]
    assert_equal "Host: web.example.com Service: CPU\n\n", @formatter.content[:text][:host_info]
  end

  def test_state_info
    @formatter.state_info
    assert_equal "State is now: <b><font style='color:red'>CRITICAL</font></b> for <b>0d 0h 0m 14s</b> (was WARNING) after <b>3 / 3</b> checks<br/><br>", @formatter.content[:html][:state_info]
    assert_equal "State is now: CRITICAL for 0d 0h 0m 14s (was WARNING) after 3 / 3 checks\n\n", @formatter.content[:text][:state_info]
  end

  def test_notification_info
    @formatter.notification_info
    assert_equal "Notification sent at: Sat May 17 01:34:07 UTC 2014 (notification number 2)<br><br>", @formatter.content[:html][:notification_info]
    assert_equal "Notification sent at: Sat May 17 01:34:07 UTC 2014 (notification number 2)\n\n", @formatter.content[:text][:notification_info]
  end

  def test_additional_info
    @formatter.additional_info
    assert_equal "<b>Additional Info</b>:<br>CRITICAL CPU <b><font color='red'>idle</font></b> is < 100%: user=3.02% system=3.25% iowait=0.01% <b><font color='red'>idle=93.72%</font></b>", @formatter.content[:html][:additional_info]
    assert_equal "Additional Info: CRITICAL CPU idle is < 100%: user=3.02% system=3.25% iowait=0.01% idle=93.72%", @formatter.content[:text][:additional_info]
  end

  def test_additional_details
    @formatter.additional_details
    puts
    assert_equal "<b>Additional Details</b>:<pre><br>TOP 5 PROCESSES BY CPU:<br> %CPU         TIME         USER    PID COMMAND<br><font color='red'> 57.6     00:00:15         root  21751 /usr/bin/ruby /usr/bin/knife search node lastrun_status:success -i</font><br><font color='orange'>  4.0     00:00:00        larry  22001 ps -eo %cpu,cputime,user,pid,args --sort -%cpu</font><br><font color='orange'>  0.7     06:19:12       nobody  12161 /usr/sbin/gmond</font><br><font color='orange'>  0.6   1-02:11:15         root   1424 [kipmi0]</font><br><font color='orange'>  0.5     00:48:01        10231  15079 mosh-server new -s -c 8 -l LANG=en_US.UTF-8</font><br></pre><br>", @formatter.content[:html][:additional_details]
    assert_equal "Additional Details:\n#TOP 5 PROCESSES BY CPU:\n %CPU         TIME         USER    PID COMMAND\n 57.6     00:00:15         root  21751 /usr/bin/ruby /usr/bin/knife search node lastrun_status:success -i\n  4.0     00:00:00        larry  22001 ps -eo %cpu,cputime,user,pid,args --sort -%cpu\n  0.7     06:19:12       nobody  12161 /usr/sbin/gmond\n  0.6   1-02:11:15         root   1424 [kipmi0]\n  0.5     00:48:01        10231  15079 mosh-server new -s -c 8 -l LANG=en_US.UTF-8\n\n\n", @formatter.content[:text][:additional_details]
  end

  def test_notes
    @formatter.notes
    # There are no notes in the example environment variables.
    assert_equal "", @formatter.content[:html][:notes]
    assert_equal "", @formatter.content[:text][:notes]
  end

  def test_action_url
    @formatter.action_url
    assert_equal "", @formatter.content[:html][:action_url]
    assert_equal "", @formatter.content[:text][:action_url]
  end

  def test_short_state_detail
    @formatter.short_state_detail
    assert_equal "CRITICAL CPU idle is < 100%: user=3.02% system=3.25% iowait=0.01% idle=93.72%<br>", @formatter.content[:html][:short_state_detail]
    assert_equal "CRITICAL CPU idle is < 100%: user=3.02% system=3.25% iowait=0.01% idle=93.72%\n", @formatter.content[:text][:short_state_detail]
  end

  def test_recipients_email_link
    @formatter.recipients_email_link
    assert_equal "Sent to ops<br><br>", @formatter.content[:html][:recipients_email_link]
    assert_equal "Sent to ops\n\n", @formatter.content[:text][:recipients_email_link]
  end

  def test_ack_info
    @formatter.ack_info
    assert_equal "At Sat May 17 01:34:07 UTC 2014  acknowledged web.example.com/CPU.<br><br>Comment: ", @formatter.content[:html][:ack_info]
    assert_equal "At Sat May 17 01:34:07 UTC 2014  acknowledged web.example.com/CPU.\n\nComment: ", @formatter.content[:text][:ack_info]
  end

  def test_short_ack_info
    @formatter.short_ack_info
    assert_equal "  ack'd CPU on web.example.com.<br>", @formatter.content[:html][:short_ack_info]
    assert_equal "  ack'd CPU on web.example.com.\n", @formatter.content[:text][:short_ack_info]
  end

  def test_alert_ack_url
    @formatter.alert_ack_url
    assert_equal "Acknowledge this alert: http://nagios.example.com/nagios/cgi-bin/cmd.cgi?cmd_typ=34&host=web.example.com&service=CPU<br>Alternatively, <b>reply</b> to this message with the word '<b><font color='green'>ack</font></b>' in the body to acknowledge the alert.<br>", @formatter.content[:html][:alert_ack_url]
    assert_equal "Acknowledge this alert: http://nagios.example.com/nagios/cgi-bin/cmd.cgi?cmd_typ=34&host=web.example.com&service=CPU\nAlternatively, reply to this message with the word 'ack' in the body to acknowledge the alert.\n", @formatter.content[:text][:alert_ack_url]
  end

  def test_clean_sandbox
    @formatter.clean_sandbox
    assert !File.directory?(@formatter.sandbox)
  end

end

