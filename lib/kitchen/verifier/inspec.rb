# encoding: utf-8
#
# Author:: Fletcher Nichol (<fnichol@chef.io>)
# Author:: Christoph Hartmann (<chartmann@chef.io>)
#
# Copyright (C) 2015, Chef Software Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'kitchen/transport/ssh'
require 'kitchen/transport/winrm'
require 'kitchen/verifier/inspec_version'
require 'kitchen/verifier/base'

require 'uri'

module Kitchen
  module Verifier
    # InSpec verifier for Kitchen.
    #
    # @author Fletcher Nichol <fnichol@chef.io>
    class Inspec < Kitchen::Verifier::Base
      kitchen_verifier_api_version 1
      plugin_version Kitchen::Verifier::INSPEC_VERSION

      # (see Base#call)
      def call(state)
        tests = helper_files + local_suite_files

        runner = ::Inspec::Runner.new(runner_options(instance.transport, state))
        runner.add_tests(tests)
        debug("Running specs from: #{tests.inspect}")
        exit_code = runner.run
        return if exit_code == 0
        fail ActionFailed, "Inspec Runner returns #{exit_code}"
      end

      private

      # Determines whether or not a local workstation file exists under a
      # Chef-related directory.
      #
      # @return [truthy,falsey] whether or not a given file is some kind of
      #   Chef-related file
      # @api private
      def chef_data_dir?(base, file)
        file =~ %r{^#{base}/(data|data_bags|environments|nodes|roles)/}
      end

      # (see Base#load_needed_dependencies!)
      def load_needed_dependencies!
        require 'inspec'
      end

      # Returns an Array of common helper filenames currently residing on the
      # local workstation.
      #
      # @return [Array<String>] array of helper files
      # @api private
      def helper_files
        glob = File.join(config[:test_base_path], 'helpers', '*/**/*')
        Dir.glob(glob).reject { |f| File.directory?(f) }
      end

      # Returns an Array of test suite filenames for the related suite currently
      # residing on the local workstation. Any special provisioner-specific
      # directories (such as a Chef roles / directory) are excluded.
      #
      # @return [Array<String>] array of suite files
      # @api private
      def local_suite_files
        base = File.join(config[:test_base_path], config[:suite_name])
        glob = File.join(base, '**/*.rb')
        Dir.glob(glob).reject do |f|
          chef_data_dir?(base, f) || File.directory?(f)
        end
      end

      # Returns a configuration Hash that can be passed to a `Inspec::Runner`.
      #
      # @return [Hash] a configuration hash of string-based keys
      # @api private
      def runner_options(transport, state = {})
        transport_data = transport.diagnose.merge(state)
        if transport.is_a?(Kitchen::Transport::Ssh)
          runner_options_for_ssh(transport_data)
        elsif transport.is_a?(Kitchen::Transport::Winrm)
          runner_options_for_winrm(transport_data)
        # optional transport which is not in core test-kitchen
        elsif defined?(Kitchen::Transport::Dokken) && transport.is_a?(Kitchen::Transport::Dokken)
          runner_options_for_docker(transport_data)
        else
          fail Kitchen::UserError, "Verifier #{name} does not support the #{transport.name} Transport"
        end.tap do |runner_options|
          runner_options['format'] = config[:format] unless config[:format].nil?
        end
      end

      # Returns a configuration Hash that can be passed to a `Inspec::Runner`.
      #
      # @return [Hash] a configuration hash of string-based keys
      # @api private
      def runner_options_for_ssh(config_data)
        kitchen = instance.transport.send(:connection_options, config_data).dup

        opts = {
          'backend' => 'ssh',
          'logger' => logger,
          # pass-in sudo config from kitchen verifier
          'sudo' => config[:sudo],
          'host' => kitchen[:hostname],
          'port' => kitchen[:port],
          'user' => kitchen[:username],
          'keepalive' => kitchen[:keepalive],
          'keepalive_interval' => kitchen[:keepalive_interval],
          'connection_timeout' => kitchen[:timeout],
          'connection_retries' => kitchen[:connection_retries],
          'connection_retry_sleep' => kitchen[:connection_retry_sleep],
          'max_wait_until_ready' => kitchen[:max_wait_until_ready],
          'compression' => kitchen[:compression],
          'compression_level' => kitchen[:compression_level],
        }
        opts['key_files'] = kitchen[:keys] unless kitchen[:keys].nil?
        opts['password'] = kitchen[:password] unless kitchen[:password].nil?

        opts
      end

      # Returns a configuration Hash that can be passed to a `Inspec::Runner`.
      #
      # @return [Hash] a configuration hash of string-based keys
      # @api private
      def runner_options_for_winrm(config_data)
        kitchen = instance.transport.send(:connection_options, config_data).dup

        opts = {
          'backend' => 'winrm',
          'logger' => logger,
          'host' => URI(kitchen[:endpoint]).hostname,
          'port' => URI(kitchen[:endpoint]).port,
          'user' => kitchen[:user],
          'password' => kitchen[:pass],
          'connection_retries' => kitchen[:connection_retries],
          'connection_retry_sleep' => kitchen[:connection_retry_sleep],
          'max_wait_until_ready' => kitchen[:max_wait_until_ready],
        }

        opts
      end

      # Returns a configuration Hash that can be passed to a `Inspec::Runner`.
      #
      # @return [Hash] a configuration hash of string-based keys
      # @api private
      def runner_options_for_docker(config_data)
        kitchen = instance.transport.send(:connection_options, config_data).dup

        opts = {
          'backend' => 'docker',
          'logger' => logger,
          'host' => kitchen[:data_container][:Id],
          'connection_timeout' => kitchen[:timeout],
          'connection_retries' => kitchen[:connection_retries],
          'connection_retry_sleep' => kitchen[:connection_retry_sleep],
          'max_wait_until_ready' => kitchen[:max_wait_until_ready],
        }

        opts
      end
    end
  end
end
