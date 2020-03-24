#
# Copyright:: 2020, Chef Software Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require_relative "../resource"
require_relative "../dist"
require_relative "helpers/cron_validations"

class Chef
  class Resource
    class ChefClientCron < Chef::Resource
      unified_mode true

      provides :chef_client_cron

      description "Use the chef_client_cron resource to setup the #{Chef::Dist::PRODUCT} to run as a cron job. This resource will also create the specified log directory if it doesn't already exist."
      introduced "16.0"
      examples <<~DOC
      Setup #{Chef::Dist::PRODUCT} to run using the default 30 minute cadence
      ```ruby
      chef_client_cron "Run chef-client as a cron job"
      ```

      Run #{Chef::Dist::PRODUCT} twice a day
      ```ruby
      chef_client_cron "Run chef-client every 12 hours" do
        minute 0
        hour "0,12"
      end
      ```

      Run #{Chef::Dist::PRODUCT} with extra options passed to the client
      ```ruby
      chef_client_cron "Run an override recipe" do
        daemon_options ["--override-runlist mycorp_base::default"]
      end
      ```
      DOC

      property :user, String,
        description: "The name of the user that #{Chef::Dist::PRODUCT} runs as.",
        default: "root"

      property :minute, [Integer, String],
        description: "The minute at which #{Chef::Dist::PRODUCT} is to run (0 - 59).",
        default: "0,30", callbacks: {
          "should be a valid minute spec" => ->(spec) { Chef::ResourceHelpers::CronValidations.validate_numeric(spec, 0, 59) },
        }

      property :hour, [Integer, String],
        description: "The hour at which #{Chef::Dist::PRODUCT} is to run (0 - 23).",
        default: "*", callbacks: {
          "should be a valid hour spec" => ->(spec) { Chef::ResourceHelpers::CronValidations.validate_numeric(spec, 0, 23) },
        }

      property :day, [Integer, String],
        description: "The day of month at which #{Chef::Dist::PRODUCT} is to run (1 - 31).",
        default: "*", callbacks: {
          "should be a valid day spec" => ->(spec) { Chef::ResourceHelpers::CronValidations.validate_numeric(spec, 1, 31) },
        }

      property :month, [Integer, String],
        description: "The month in the year on which #{Chef::Dist::PRODUCT} is to run (1 - 12, jan-dec, or *).",
        default: "*", callbacks: {
          "should be a valid month spec" => ->(spec) { Chef::ResourceHelpers::CronValidations.validate_month(spec) },
        }

      property :weekday, [Integer, String],
        description: "The day of the week on which #{Chef::Dist::PRODUCT} is to run (0-7, mon-sun, or *), where Sunday is both 0 and 7.",
        default: "*", callbacks: {
          "should be a valid weekday spec" => ->(spec) { Chef::ResourceHelpers::CronValidations.validate_dow(spec) },
        }

      property :mailto, String

      property :job_name, String,
        default: Chef::Dist::CLIENT,
        description: "The name of the cron job to create."

      property :splay, [Integer, String],
        default: 300,
        description: "A random number of seconds between 0 and X to add to interval so that all #{Chef::Dist::CLIENT} commands don't execute at the same time."

      property :environment, Hash,
        default: lazy { {} },
        description: "A Hash containing additional arbitrary environment variables under which the cron job will be run in the form of ``({'ENV_VARIABLE' => 'VALUE'})``."

      property :comment, String,
        description: "A comment to place in the cron.d file."

      property :config_directory, String,
        default: Chef::Dist::CONF_DIR,
        description: "The path of the config directory."

      property :log_directory, String,
        default: lazy { platform?("mac_os_x") ? "/Library/Logs/#{Chef::Dist::DIR_SUFFIX.capitalize}" : "/var/log/#{Chef::Dist::DIR_SUFFIX}" },
        description: "The path of the directory to create the log file in."

      property :log_file_name, String,
        default: "client.log",
        description: "The name of the log file to use."

      property :append_log_file, [true, false],
        default: false,
        description: "Append to the log file instead of creating a new file on each run."

      property :chef_binary_path, String,
        default: "/opt/#{Chef::Dist::DIR_SUFFIX}/bin/#{Chef::Dist::CLIENT}",
        description: "The path to the #{Chef::Dist::CLIENT} binary."

      property :daemon_options, Array,
        default: [],
        description: "An array of options to pass to the #{Chef::Dist::CLIENT} command."

      action :add do
        # TODO: Replace this with a :create_if_missing action on directory when that exists
        unless ::Dir.exist?(new_resource.log_directory)
          directory new_resource.log_directory do
            owner new_resource.user
            mode "0640"
            recursive true
          end
        end

        cron_d new_resource.job_name do
          minute  new_resource.minute
          hour    new_resource.hour
          day     new_resource.day
          weekday new_resource.weekday
          month   new_resource.month
          mailto  new_resource.mailto if new_resource.mailto
          user    new_resource.user
          comment new_resource.comment if new_resource.comment
          command cron_command
        end
      end

      action :remove do
        cron_d new_resource.job_name do
          action :delete
        end
      end

      action_class do
        # Generate a uniformly distributed unique number to sleep.
        def splay_sleep_time(splay)
          if splay.to_i > 0
            seed = node["shard_seed"] || Digest::MD5.hexdigest(node.name).to_s.hex
            seed % splay.to_i
          end
        end

        def cron_command
          cmd = ""
          cmd << "/bin/sleep #{splay_sleep_time(new_resource.splay)}; "
          cmd << "#{new_resource.environment} " unless new_resource.environment.empty?
          cmd << "#{new_resource.chef_binary_path} "
          cmd << "#{new_resource.daemon_options.join(" ")} " unless new_resource.daemon_options.empty?
          cmd << "#{new_resource.append_log_file ? ">>" : ">"} #{::File.join(new_resource.log_directory, new_resource.log_file_name)} 2>&1"
          cmd << " || echo \"#{Chef::Dist::PRODUCT} execution failed\"" if new_resource.mailto
          cmd
        end
      end
    end
  end
end
