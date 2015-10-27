#
# Copyright:: Copyright (c) 2015 Chef Software, Inc.
# License:: Apache License, Version 2.0
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

require 'chef/provider/package'
require 'chef/resource/chocolatey_package'
require 'chef/mixin/powershell_out'

class Chef
  class Provider
    class Package
      class Chocolatey < Chef::Provider::Package
        include Chef::Mixin::PowershellOut

        provides :chocolatey_package, os: "windows"

        # Declare that our arguments should be arrays
        package_class_supports_arrays

        # Responsible for building the current_resource and as a (necessary)
        # side effect this populates the candidate_version Array.
        #
        # @return [Chef::Resource::ChocolateyPackage] the current_resource
        def load_current_resource
          current_resource = Chef::Resource::ChocolateyPackage.new(new_resource.name)
          current_resource.package_name(new_resource.package_name)
          current_resource.version(build_current_versions)
          @candidate_version = build_candidate_versions
          current_resource
        end

        # Define provider-specific exceptions
        def define_resource_requirements
          super

          # this is an error even in why-run mode
          if new_resource.source
            raise Chef::Exceptions::Package, 'chocolatey package provider cannot handle source attribute.'
          end
        end

        # Install multiple packages via choco.exe
        #
        # @param name [Array<String>] array of package names to install
        # @param version [Array<String>] array of versions to install
        def install_package(name, version)
          name_versions = name_array.zip(version_array)

          name_nil_versions = name_versions.select { |n,v| v.nil? }
          name_has_versions = name_versions.reject { |n,v| v.nil? }

          # choco does not support installing multiple packages with version pins
          name_has_versions.each do |name, version|
            shell_out!("#{choco_exe} install -y -version #{version} #{cmd_args} #{name}")
          end

          # but we can do all the ones without version pins at once
          unless name_nil_versions.empty?
            names = name_nil_versions.keys.join(' ')
            shell_out!("#{choco_exe} install -y #{cmd_args} #{names}")
          end
        end

        # Upgrade multiple packages via choco.exe
        #
        # @param name [Array<String>] array of package names to install
        # @param version [Array<String>] array of versions to install
        def upgrade_package(name, version)
          unless version.all? { |n,v| v.nil? }
            raise Chef::Exceptions::Package, "Chocolatey Provider does not support version pins on upgrade command, use install instead"
          end

          names = name.join(' ')
          shell_out!("#{choco_exe} upgrade -y #{cmd_args} #{names}")
        end

        # Remove multiple packages via choco.exe
        #
        # @param name [Array<String>] array of package names to install
        # @param version [Array<String>] array of versions to install
        def remove_package(name, version)
          names = name.join(' ')
          shell_out!("#{choco_exe} uninstall -y #{cmd_args} #{names}")
        end

        # Support :uninstall as an action in order for users to easily convert
        # from the `chocolatey` provider in the cookbook.  This lands in the
        # code in deprecated form since we do not want to support :uninstall as
        # a valid action on any other package provider.
        def uninstall_package(name, version)
          Chef::Log.deprecation "The use of action :uninstall on the chocolatey_package provider is deprecated, please use :remove"
          remove_package(name, version)
        end

        # Choco does not have dpkg's distinction between purge and remove
        alias_method :purge_package, :remove_package

        private

        # Magic to find where chocolatey is installed in the system, and to
        # return the full path of choco.exe
        #
        # @return [String] full path of choco.exe
        def choco_exe
          @choco_exe ||=
            ::File.join(
              powershell_out!(
                "[System.Environment]::GetEnvironmentVariable('ChocolateyInstall', 'MACHINE')"
              ).stdout.chomp,
              'bin',
              'choco.exe'
          )
        end

        def build_candidate_versions
          if new_resource.name.is_a?(Array)
            # FIXME: superclass should be made smart enough so that when we declare
            # package_class_supports_arrays, then it accepts current_resource.version as an
            # array when new_resource.name is not
            new_resource.name.map do |name|
              available_packages[name]
            end
          else
            available_packages[new_resource.name]
          end
        end

        def build_current_versions
          if new_resource.name.is_a?(Array)
            # FIXME: superclass should be made smart enough so that when we declare
            # package_class_supports_arrays, then it accepts current_resource.version as an
            # array when new_resource.name is not
            new_resource.name.map do |name|
              installed_packages[name]
            end
          else
            installed_packages[new_resource.name]
          end
        end

        # Helper to pull optional args out of new_resource
        #
        # @return [String] options from new_resource or empty string
        def cmd_args
          new_resource.options || ""
        end

        # Available packages in chocolatey as a Hash of names mapped to versions
        #
        # @return [Hash] name-to-version mapping of available packages
        def available_packages
          @available_packages ||= parse_list_output("list -r")
        end

        # Insatlled packages in chocolatey as a Hash of names mapped to versions
        #
        # @return [Hash] name-to-version mapping of installed packages
        def installed_packages
          @installed_packages ||= parse_list_output("list -l -r")
        end

        # Helper to convert choco.exe list output to a Hash
        #
        # @param cmd [String] command to run
        # @return [String] list output converted to ruby Hash
        def parse_list_output(cmd)
          hash = {}
          shell_out!("#{choco_exe} #{cmd}").stdout.each_line do |line|
            name, version = line.split('|')
            hash[name] = version
          end
          hash
        end
      end
    end
  end
end
