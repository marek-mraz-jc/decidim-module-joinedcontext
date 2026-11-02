# frozen_string_literal: true

require "net/http"

module Decidim
  module Joinedcontext
    # Writes entities through a target Endpoint with a client-credentials token. Every call has
    # timeouts and size caps and follows no redirect; no answer text reaches a log unread.
    class Client
      # What an admin reads in the status line; never holds a token or the client secret.
      class Error < StandardError; end

      # The Endpoint or the realm is away for now; the job tries again.
      class Unavailable < Error; end

      BATCH = 100
      MAX_BODY = 1.megabyte
      MAX_ANSWER = 256.kilobytes
      TIMEOUTS = { open_timeout: 5, read_timeout: 30, write_timeout: 30 }.freeze
      NETWORK_ERRORS = [SocketError, SystemCallError, Timeout::Error, IOError, OpenSSL::SSL::SSLError].freeze
      TOKENS = Concurrent::Map.new

      Answer = Struct.new(:code, :body) do
        def success?
          code.between?(200, 299)
        end
      end

      def initialize(target)
        @target = target
      end

      def write_entities(entities)
        split(entities) { |part| write("entityOperations/upsert?options=update", part) }
      end

      def delete_entities(ids)
        write("entityOperations/delete", ids, missing_is_gone: true)
      end

      private

      attr_reader :target

      # An Endpoint takes a body of 4 MiB; a batch of long texts halves until it is well under that.
      def split(entities, &)
        return yield(entities) if entities.size == 1 || entities.to_json.bytesize <= MAX_BODY

        entities.each_slice((entities.size + 1) / 2) { |part| split(part, &) }
      end

      def write(path, body, missing_is_gone: false)
        raise Error, I18n.t("decidim.joinedcontext.errors.host") unless target.allowed?

        answer = post(path, body, token)
        if answer.code == 401
          TOKENS.delete(client_id)
          answer = post(path, body, token)
        end
        judge(answer, body.size, missing_is_gone)
      end

      def post(path, body, bearer)
        uri = URI.parse("#{target.url}/ngsi-ld/v1/#{path}")
        request = Net::HTTP::Post.new(uri, "Authorization" => "Bearer #{bearer}", "Content-Type" => "application/json", "Accept" => "application/json")
        request.body = body.to_json
        send_request(uri, request)
      end

      def send_request(uri, request)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", **TIMEOUTS) do |http|
          http.request(request) { |response| return Answer.new(response.code.to_i, read_capped(response, uri.host)) }
        end
      rescue *NETWORK_ERRORS => e
        raise Unavailable, I18n.t("decidim.joinedcontext.errors.unreachable", host: uri.host, reason: e.class.name)
      end

      def read_capped(response, host)
        body = +""
        response.read_body do |chunk|
          body << chunk
          raise Unavailable, I18n.t("decidim.joinedcontext.errors.oversized", host:) if body.bytesize > MAX_ANSWER
        end
        body
      end

      def judge(answer, count, missing_is_gone)
        code = answer.code
        return judge_partial(answer, count, missing_is_gone) if code == 207
        return if answer.success?
        raise Unavailable, I18n.t("decidim.joinedcontext.errors.unavailable", code:) if code == 429 || code >= 500

        raise Error, I18n.t("decidim.joinedcontext.errors.refused", code:, reason: problem(answer.body))
      end

      # 207: the entities the broker took stay; one it refused fails the run (CIM 009 6.17). A delete
      # of an entity the broker lacks reached its goal: a draft was never published, so it has none.
      def judge_partial(answer, count, missing_is_gone)
        refused = Array(parsed(answer.body)["errors"]).map { |row| row_problem(row) }
        refused = refused.reject { |problem| problem["type"].to_s.end_with?("/ResourceNotFound") } if missing_is_gone
        return if refused.empty?

        raise Error, I18n.t("decidim.joinedcontext.errors.partial", refused: refused.size, count:, reason: refused.first["title"].to_s.first(200))
      end

      def row_problem(row)
        problem = row.is_a?(Hash) ? row["error"] : nil
        problem.is_a?(Hash) ? problem : {}
      end

      def problem(body)
        details = parsed(body)
        [details["title"], details["detail"]].compact.join(": ").first(200)
      end

      def parsed(body)
        value = JSON.parse(body)
        value.is_a?(Hash) ? value : {}
      rescue JSON::ParserError
        {}
      end

      def token
        kept = TOKENS[client_id]
        return kept[:value] if kept && kept[:until] > Time.current

        answer = fetch_token
        TOKENS[client_id] = { value: answer.fetch("access_token"), until: answer.fetch("expires_in").to_i.seconds.from_now - 30.seconds }
        answer.fetch("access_token")
      rescue KeyError
        raise Error, I18n.t("decidim.joinedcontext.errors.token")
      end

      def fetch_token
        uri = URI.parse(ENV.fetch("JOINEDCONTEXT_TOKEN_URL"))
        request = Net::HTTP::Post.new(uri, "Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json")
        request.body = URI.encode_www_form(grant_type: "client_credentials", client_id:, client_secret: ENV.fetch("JOINEDCONTEXT_CLIENT_SECRET"))
        answer = send_request(uri, request)
        raise Unavailable, I18n.t("decidim.joinedcontext.errors.unavailable", code: answer.code) if answer.code >= 500
        raise Error, I18n.t("decidim.joinedcontext.errors.token") unless answer.success?

        parsed(answer.body)
      end

      def client_id
        ENV.fetch("JOINEDCONTEXT_CLIENT_ID")
      end
    end
  end
end
