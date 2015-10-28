#
# Author:: Adam Jacob (<adam@opscode.com>)
# Copyright:: Copyright (c) 2008-2015 Chef Software, Inc.
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

require 'spec_helper'

describe Chef::Provider::Package::Chocolatey do
  let(:new_resource) { Chef::Resource::ChocolateyPackage.new("git") }

  let(:current_resource) { Chef::Resource::ChocolateyPackage.new("git") }

  let(:provider) do
    node = Chef::Node.new
    events = Chef::EventDispatch::Dispatcher.new
    run_context = Chef::RunContext.new(node, {}, events)
    Chef::Provider::Package::Chocolatey.new(new_resource, run_context)
  end

  let(:choco_exe) { 'C:\ProgramData\chocolatey\bin\choco.exe' }

  before do
    allow(provider).to receive(:choco_exe).and_return(choco_exe)
  end

  describe "#initialize" do
    it "should return the correct class" do
      expect(provider).to be_kind_of(Chef::Provider::Package::Chocolatey)
    end

    it "should have a candidate_version attribute" do
      expect(provider.candidate_version).to be nil
    end
  end

  describe "#load_current_resource" do
    let(:local_list_stdout) do
      <<-EOF
chocolatey|0.9.9.11
ConEmu|15.10.25.0
      EOF
    end

    let(:remote_list_stdout) do
      <<-EOF
chocolatey|0.9.9.11
ConEmu|15.10.25.1
git|2.6.2
      EOF
    end

    before do
      local_list_obj = double(:stdout => local_list_stdout)
      allow(provider).to receive(:shell_out!).with("#{choco_exe} list -l -r", {:timeout => 900}).and_return(local_list_obj)
      remote_list_obj = double(:stdout => remote_list_stdout)
      allow(provider).to receive(:shell_out!).with("#{choco_exe} list -r", {:timeout => 900}).and_return(remote_list_obj)
    end

    it "should return a current_resource" do
      expect(provider.load_current_resource).to be_kind_of(Chef::Resource::ChocolateyPackage)
    end

    it "should set the current_resource#package_name" do
      provider.load_current_resource
      expect(provider.current_resource.package_name).to eql(["git"])
    end

    it "should load and downcase names in the installed_packages hash" do
      provider.load_current_resource
      expect(provider.send(:installed_packages)).to eql(
        {"chocolatey"=>"0.9.9.11", "conemu"=>"15.10.25.0"}
      )
    end

    it "should load and downcase names in the available_packages hash" do
      provider.load_current_resource
      expect(provider.send(:available_packages)).to eql(
        {"chocolatey"=>"0.9.9.11", "conemu"=>"15.10.25.1", "git"=>"2.6.2"}
      )
    end

    it "should set the current_resource.version to nil when the package is not installed" do
      provider.load_current_resource
      expect(provider.current_resource.version).to eql([nil])
    end

    it "should set the current_resource.version to the installed version when the package is installed" do
      new_resource.package_name("ConEmu")
      provider.load_current_resource
      expect(provider.current_resource.version).to eql(["15.10.25.0"])
    end

    it "should set the current_resource.version when there are two packages that are installed" do
      new_resource.package_name(["ConEmu", "chocolatey"])
      provider.load_current_resource
      expect(provider.current_resource.version).to eql(["15.10.25.0", "0.9.9.11"])
    end

    it "should set the current_resource.version correctly when only the first is installed" do
      new_resource.package_name(["ConEmu", "git"])
      provider.load_current_resource
      expect(provider.current_resource.version).to eql(["15.10.25.0", nil])
    end

    it "should set the current_resource.version correctly when only the last is installed" do
      new_resource.package_name(["git", "chocolatey"])
      provider.load_current_resource
      expect(provider.current_resource.version).to eql([nil, "0.9.9.11"])
    end

    it "should set the current_resource.version correctly when none are installed" do
      new_resource.package_name(["git", "vim"])
      provider.load_current_resource
      expect(provider.current_resource.version).to eql([nil, nil])
    end

    it "should set the candidate_version correctly" do
      provider.load_current_resource
      expect(provider.candidate_version).to eql(["2.6.2"])
    end

    it "should set the candidate_version to nil if there is no candidate" do
      new_resource.package_name("vim")
      provider.load_current_resource
      expect(provider.candidate_version).to eql([nil])
    end

    it "should set the candidate_version correctly when there are two packages to install" do
      new_resource.package_name(["ConEmu", "chocolatey"])
      provider.load_current_resource
      expect(provider.candidate_version).to eql(["15.10.25.1", "0.9.9.11"])
    end

    it "should set the candidate_version correctly when only the first is installable" do
      new_resource.package_name(["ConEmu", "vim"])
      provider.load_current_resource
      expect(provider.candidate_version).to eql(["15.10.25.1", nil])
    end

    it "should set the candidate_version correctly when only the last is installable" do
      new_resource.package_name(["vim", "chocolatey"])
      provider.load_current_resource
      expect(provider.candidate_version).to eql([nil, "0.9.9.11"])
    end

    it "should set the candidate_version correctly when neither are is installable" do
      new_resource.package_name(["vim", "ruby"])
      provider.load_current_resource
      expect(provider.candidate_version).to eql([nil, nil])
    end

  end

#  describe "#action_install" do
#  end
#
#  describe "#action_remove" do
#  end
#
#  describe "#action_upgrade" do
#  end
#
#  describe "#action_uninstall" do
#  end
end
