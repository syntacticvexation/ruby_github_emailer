require_relative "github_emailer/version"

require 'erb'
require 'github_api'
require 'easy_diff'
require 'pony'
require 'yaml/store'

module GithubEmailer
	class Runner
		def read_config
			 @config = YAML.load_file(File.expand_path('~/.github_emailer_config.yml')).inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
		end

		def process_cache_and_generate_message_body
			Github.configure do |config|
		  		config.stack do |builder|
		    		builder.use Faraday::HttpCache, store: Rails.cache
				end
			end

			store = YAML::Store.new(File.expand_path('~/.github_emailer_cache.yml'))
			store.transaction do
				# read cache
				old_repo_data = store[:repos]

				# grab data from github, put into a hash
				latest_repo_data = Github.repos.list(user: @config[:github_user])
	
				repos = {}
				latest_repo_data.each{|repo|
					things = [:forks]
					things.each {|thing|
						latest_thing_data = Github.repos.send(thing).list @config[:github_user], repo[:name]			
						things[thing] = latest_thing_data.map(&:owner).map(&:login)
			 			
			 			repos[repo[:name]] = things
					}
				}
					
				removed, added = old_repo_data.easy_diff repos
				
				# generate message body
				renderer = ERB.new(File.read(File.expand_path("../github_emailer.html.erb", __FILE__)))
				@msg_body = renderer.result(binding())
				@change_count =  added.count

				# write cache
				store[:timestamp] =  Time.now		
				store[:repos] = repos
			end
		end

		def email_update
			Pony.mail(:to => @config[:email_address], :from => @config[:email_address],:subject => "[github Status Update for #{@config[:github_user]}] - #{@change_count} change#{@change_count == 1 ? '' : 's'}", :html_body => @msg_body)
		end
	
		def self.run
			github_emailer = GithubEmailer::Runner.new

			github_emailer.read_config
			github_emailer.process_cache_and_generate_message_body
			github_emailer.email_update
		end
	end

	GithubEmailer::Runner::run
end
