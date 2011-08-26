begin
  require 'json'
rescue LoadError
  raise "json gem is missing.  Please install json: gem install json"
end

Heroku::Command::Help.group("Ranger") do |group|
  group.command "ranger",                      "show current app status"
  group.command "ranger:domains",              "list domains being monitored"
  group.command "ranger:domains add <url>",    "start monitoring a domain"
  group.command "ranger:domains remove <url>", "stop monitoring a domain"
  group.command "ranger:domains clear",        "stop monitoring all domains"
  group.command "ranger:watchers",               "list current app watchers"
  group.command "ranger:watchers add <email>",   "add an app watcher"
  group.command "ranger:watchers remove <email>",   "remove an app watcher"
  group.command "ranger:watchers clear",        "remove all app watchers"
end

module Heroku::Command
  class Ranger < BaseWithApp
    def initialize(*args)
      super
      @config_vars = heroku.config_vars(app)
      @ranger_api_key = ENV["RANGER_API_KEY"] || @config_vars["RANGER_API_KEY"]
      @ranger_app_id = ENV["RANGER_APP_ID"] || @config_vars["RANGER_APP_ID"]
      @app_owner = heroku.info(app)[:owner]
      abort(" !   Please add the ranger addon first.") unless @ranger_api_key
    end

    def index
      if get_status
        dependencies = @current_status
        
        puts "\nRanger Status"
        puts "------------------------------------------"

        dependencies.each do |record|
          url = record["dependency"]["url"]
          code = record["dependency"]["latest_response_code"]
          puts "#{url} #{up_or_down(code)}"
        end
        
        watchers_list
      else
        no_domains_monitored
      end
    end

    def domains
      if args.empty?
        domain_list
        return
      end
      
      case args.shift
        when "add"
          url = args.shift
          create_dependency(url)
          puts "Added #{url} to the monitoring list"
          return
        when "remove"
          url = args.shift
          remove_url(url)
          return
        when "clear"
          clear_all_dependencies
          puts "All domains removed from the monitoring list"
          return
      end
      raise(CommandFailed, "usage: heroku ranger:domains <add | remove | clear>")
    end

    def watchers
      if args.empty?
        watchers_list
        return
      end

      case args.shift
        when "add"
          email = args.shift
          create_watcher(email)
          puts "Added #{email} as a watcher"
          return
        when "remove"
          email = args.shift
          remove_watcher(email)
          return
        when "clear"
          clear_all_watchers
          puts "All watchers removed"
          return
      end
      raise(CommandFailed, "usage: heroku ranger:watchers <add | remove | clear>")
    end
  
    protected

    def authenticated_resource(path)
      host = "https://rangerapp.com/api/v1"
      RestClient::Resource.new("#{host}#{path}")
    end

    def up_or_down(code)
      case code
      when 200
        "is UP"
      when nil
        "=> not checked yet"
      else
        "is DOWN with status code #{code}"
      end
    end

    def get_status
      resource = authenticated_resource("/status/#{@ranger_app_id}?api_key=#{@ranger_api_key}")

      begin
        @current_status = JSON.parse(resource.get)
        true
      rescue RestClient::ResourceNotFound => e
        false
      end
    end

    def get_dependencies
      resource = authenticated_resource("/apps/#{@ranger_app_id}/dependencies.json?api_key=#{@ranger_api_key}")
      resource.get
    end

    def create_dependency(url)
      resource = authenticated_resource("/apps/#{@ranger_app_id}/dependencies.json")
      params = { :dependency => { :name => "Website", :url => url, :check_every => "1" }, :api_key => @ranger_api_key}
      resource.post(params)
    end
    
    def remove_url(url)
      if delete_dependency_from_url(url)
        puts "Removed #{url} from the monitoring list"
      else
        puts "No domain with that URL found in the monitoring list"
      end
    end

    def delete_dependency_from_url(url)
      dependencies = JSON.parse(get_dependencies)
      
      dependency_id = nil
      dependencies.each do |record|
        if record["dependency"]["url"] == url
          dependency_id = record["dependency"]["id"]
          delete_dependency(dependency_id)
        end
      end
      return false if dependency_id.nil?
      return true
    end

    def delete_dependency(id)
      resource = authenticated_resource("/apps/#{@ranger_app_id}/dependencies/#{id}.json?api_key=#{@ranger_api_key}")

      begin
        resource.delete
      rescue RestClient::ResourceNotFound => e
        false
      end
    end

    def clear_all_dependencies
      dependencies = JSON.parse(get_dependencies)
      
      dependencies.each do |record|
        delete_dependency(record["dependency"]["id"])
      end
    end
    
    def clear_all_watchers
      watchers = get_watchers
      
      watchers.each do |record|
        delete_watcher(record["watcher"]["id"])
      end
    end

    def no_domains_monitored
      puts "\n---------------------------------------------"
      puts "No domains are being monitored for this app."
      puts "-----------------------------------------------"
      puts "\nMonitor a domain like this:"
      puts "\n  heroku ranger:domains add http://yourapp.heroku.com\n\n"
    end

    def domain_list
      if get_status
        dependencies = @current_status
        
        puts "\nDomains Being Monitored"
        puts "------------------------------------------"

        dependencies.each do |record|
          url = record["dependency"]["url"]
          code = record["dependency"]["latest_response_code"]
          puts "#{url}"
        end
        puts ""
      else
        no_domains_monitored
      end
    end

    def get_watchers
      resource = authenticated_resource("/apps/#{@ranger_app_id}/watchers.json?api_key=#{@ranger_api_key}")
      @current_watchers = JSON.parse(resource.get)
    end

    def watchers_list
      get_watchers
      
      puts "\nApp Watchers"
      puts "------------------------------------------"

      @current_watchers.each do |record|
        email = record["watcher"]["email"]
        puts "#{email}"
      end
      puts ""
    end
    
    def create_watcher(email)
      resource = authenticated_resource("/apps/#{@ranger_app_id}/watchers.json")
      params = { :watcher => { :email => email }, :api_key => @ranger_api_key}
      resource.post(params)
    end
    
    def remove_watcher(email)
      if delete_watcher_from_email(email)
        puts "Removed #{email} as a watcher"
      else
        puts "No watchers with that email found in the watcher list"
      end
    end
    
    def delete_watcher_from_email(email)
      watchers = get_watchers
      
      watcher_id = nil
      watchers.each do |record|
        if record["watcher"]["email"] == email
          watcher_id = record["watcher"]["id"]
          delete_watcher(watcher_id)
        end
      end
      return false if watcher_id.nil?
      return true
    end

    def delete_watcher(id)
      resource = authenticated_resource("/apps/#{@ranger_app_id}/watchers/#{id}.json?api_key=#{@ranger_api_key}")

      begin
        resource.delete
      rescue RestClient::ResourceNotFound => e
        false
      end
    end
  end
end
