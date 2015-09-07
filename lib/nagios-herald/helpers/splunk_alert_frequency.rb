require 'net/http'
require 'uri'
require 'json'

# Use Splunk to search for previous occurrences of a given Nagios alert and
# report.
#
# Can search for host alerts (i.e. DOWN state) and service alerts for a
# single host (i.e. 'Disk Space' is CRITICAL).
#
# Options:
#  :duration - time (in days) to search [DEFAULT: 7 days]
#  :hostname - Etsy Nagios-like hostname (i.e. web0200.ny4) [REQUIRED]
#  :service_name - service name to search (i.e. 'Disk Space) [OPTIONAL]
#
#  If the :service_name argument is not present, this performs a search
#  for host alerts.

module NagiosHerald
  module Helpers
    class SplunkReporter
      include NagiosHerald::Logging

      # Public: Initialize a new SplunkReporter object.
      #
      # splunk_url - The URI of the Splunk search API.
      # username - A username that's authorized to perform Splunk queries.
      # password - Yeah, a password.
      #
      # Returns a new SplunkReporter object.
      def initialize(splunk_url, username, password)
        uri = URI.parse( splunk_url )
        @splunk_host = uri.host
        @splunk_port = uri.port
        @splunk_uri  = uri.request_uri

        @username      = username
        @password      = password
        @fields = ['hostname', 'service_name', 'state', 'date_year', 'date_month', 'date_mday', 'date_hour', 'date_minute']
      end

      # Public: Generate the Splunk query.
      #
      # hostname - The name of the alerting host we want to query.
      # service - Optional service name that may be alerting.
      #
      # Returns the generated Splunk query.
      def get_splunk_alert_query(hostname, service = nil)
        # query for service alerts or host alerts, depending on which args were selected
        query = "search index=nagios hostname=\"#{hostname}\""
        if service.nil?
            query += " state=\"DOWN\""
        else
            query += " service_name=\"#{service}\" (state=\"WARNING\" OR state=\"CRITICAL\" OR state=\"UNKNOWN\" OR state=\"DOWN\")"
        end
        query +=  "| fields #{@fields.join(',')}"
        return query
      end

      # Public: Queries Splunk to determine how frequently an alert has fired in a given period.
      #
      # hostname - The name of the alerting host we want to query.
      # service - Optional service name that may be alerting.
      # options - The options hash containing parameters for manipulatin the query.
      #
      # Returns a hash containing results from the search.
      def get_alert_frequency(hostname, service = nil, options = {})
        duration = options[:duration] ? options[:duration] : 7

        max_results = options[:max_results] ? options[:max_results] : 10000

        latest_time = options[:latest_time] ? options[:latest_time] :"now"

        params = {
            'exec_mode'     => 'oneshot',
            'earliest_time' => "-#{duration}d",
            'latest_time'   => latest_time,
            'output_mode'   => 'json',
            'count'         => max_results
        }

        params['search'] = get_splunk_alert_query(hostname, service)

        json_response = query_splunk(params)

        return if json_response.nil?

        events_count = aggregate_splunk_events(json_response)

        duration.to_i > 1 ? period = "days" : period = "day"
        return {
            :period   => "#{duration} #{period}",
            :service  => service,
            :hostname => hostname,
            :events_count => events_count
        }
      end

      # Public: Performs the Splunk query.
      #
      # params - The parameters of the query.
      #
      # Returns the JSON results from the query.
      def query_splunk(params)
        http = Net::HTTP.new( @splunk_host, @splunk_port )
        http.use_ssl = true
        http.open_timeout = 1
        http.read_timeout = 2
        http.ssl_timeout = 1
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE    # don't validate the cert
        request = Net::HTTP::Post.new( @splunk_uri )
        request.basic_auth( @username, @password )
        request.set_form_data( params )
        response = http.request( request )
        unless response.code.eql?( "200" )
          logger.warn "Failed to submit search to Splunk."
          return nil
        end

        begin
          json = JSON.parse( response.body )
        rescue Exception => e
          # just warn; our formatter should handle this gracefully
          logger.warn(e.message)
          logger.warn("Failed to parse response from Splunk. Perhaps we got an empty result?")
          return nil
        end

        return json
      end

      # Public: Aggregate the results from Splunk.
      # Nagios logs an entry for each entity that got alerted; a single alert can
      # result in many log entries so we need to account for this by creating a
      # unique key to ensure we don't count duplicate log lines.
      # Chances are we *won't* see a duplicate except in cases where an alert fires
      # on the cusp of a minute (I've seen up to 4-second skew in timestamp for
      # alert results returned from Splunk; this _can_ happen).
      #
      # json - The Splunk query results in JSON.
      #
      # Returns a string containing a message useful for outputting into a notification.
      def aggregate_splunk_events(json)
        events = {}
        json.each do |alert|
            state = alert['state']
            event_key = @fields.map{|f| alert[f]}.join('-')
            state_els = events.fetch(state, [])
            events[state] = state_els << event_key
        end

        # get the alert counts by state
        events_count = {}
        events.map {|k,v| events_count[k] = v.uniq.count}
        events_count.sort_by {|k,v| v}.reverse
        return events_count
      end

      def format_splunk_results(events_count, hostname, duration, service=nil)
        # speaka da English
        duration.to_i > 1 ? period = "days" : period = "day"
        msg = "HOST '#{hostname}' has experienced #{events_count.join(', ')} alerts"
        msg += " for SERVICE '#{service}'" unless service.nil?
        msg += " in the last #{duration} #{period}."
        return msg
      end

    end
  end
end
