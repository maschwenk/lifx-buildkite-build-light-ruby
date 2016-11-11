require 'rack/parser'
require 'sinatra'
require 'json'
require 'slack-notifier'
require 'awesome_print'
require 'octokit'
require 'buildkit'
require 'yaml'

# Required
set :webhook_token, ENV['WEBHOOK_TOKEN'] || raise("no WEBHOOK_TOKEN set")
set :slack_webhook_url, ENV['SLACK_WEBHOOK_URL'] || raise("no SLACK_WEBHOOK_URL set")
set :github_api_key, ENV['GITHUB_API_KEY'] || raise("no GITHUB_API_KEY set")
set :builkit_api_key, ENV['BUILDKIT_API_KEY'] || raise("no BUILDKIT_API_KEY set")


use Rack::Parser # loads the JSON request body into params

# Without some really wonky API calls and some guesswork, its very hard to get these
github_to_slackname_mapping = YAML.load_file(['config','github_slack_user_mapping.yml'].join("/"))

notifier = Slack::Notifier.new settings.slack_webhook_url
github_client = Octokit::Client.new :access_token =>  settings.github_api_key
buildkit = Buildkit.new(token: settings.builkit_api_key)

post "/buildkite" do
  buildkite_event = request.env['HTTP_X_BUILDKITE_EVENT']

  halt 401 unless request.env['HTTP_X_BUILDKITE_TOKEN'] == settings.webhook_token

  ap params

  build = params[:build]

  slack_formatted_buildkite_url = slack_formatted_url(build[:web_url], "here")

  pull_request_id = build.dig(:pull_request, :id)

  # TODO: Generify this
  pr = github_client.pull_request "bugcrowd/bugcrowd", pull_request_id # This is a Sawyer object, not a hash

  pull_request_url, pull_request_branch, github_author = pr[:html_url], pr[:head][:ref], pr[:user][:login]

  slack_formatted_github_url = slack_formatted_url(pull_request_url, "#{pull_request_branch} (#{pull_request_id})")

  slackname = github_to_slackname_mapping[github_author]

  case buildkite_event
  when 'build.finished'
    if params.dig(:build, :state) == 'passed'
      notifier.ping ":thumbsup: :thumbsup: Build passed for #{slack_formatted_github_url}, find the status #{slack_formatted_buildkite_url}"
    else
      notifier.ping ":thumbsdown: :thumbsdown: :fire: :fire: Build failed for #{slack_formatted_github_url}, find the status #{slack_formatted_buildkite_url}"
    end
  when 'build.scheduled'
    notifier.ping ":building_construction: :building_construction: Build started for #{slack_formatted_github_url}, find the status #{slack_formatted_buildkite_url}"
  else
    ap "Unhandled event: #{buildkite_event}"
  end

  status 200
end

def slack_formatted_url(url, display_text)
  "<#{url}|#{display_text}>"
end
