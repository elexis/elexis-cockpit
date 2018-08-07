# encoding: utf-8
# Copyright (c) 2013 by Niklaus Giger niklaus.giger@member.fsf.org

require 'rspec'
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib/','elexis_helpers.rb'))
include Sinatra::ElexisHelpers
require 'yaml'
require 'socket'

  # examples taken from Peter Schönbucher March 2013
  mdstat_okay = %(
Personalities : [raid1]
md0 : active raid1 sda1[0] sdb1[1]
      5060352 blocks [2/2] [UU]

md1 : active raid1 sda2[0] sdb2[1]
      82092032 blocks [2/2] [UU]

unused devices: <none>
)

describe 'RaidInfo' do
  mdBadFile = '/tmp/should_not_exists'

  mdstat_degraded = %(
Personalities : [raid1]
md0 : active raid1 sda1[0] sdb1[1]
      5060352 blocks [2/2] [_U]

md1 : active raid1 sda2[0] sdb2[1]
      82092032 blocks [2/2] [UU]

unused devices: <none>
)
  before :each do
    @okay = RaidInfo.new(RaidInfo::MdStat, mdstat_okay)
    @degraded = RaidInfo.new(RaidInfo::MdStat, mdstat_degraded)
  end

  it "should cope with not existing /proc/mdstat" do
    expect(RaidInfo.new(mdBadFile).active).to be_nil
    expect(RaidInfo.new(mdBadFile).degraded).to be_nil
    expect(RaidInfo.new(mdBadFile).getComponents('x')).to be_nil
  end

  it "should return raw info" do
    expect(@okay.raw).to eq(mdstat_okay)
  end

  it "return active assemblies" do
    expect(@okay.active).to     eq([ 'md0', 'md1' ])
    expect(@degraded.active).to eq([ 'md0', 'md1' ])
  end

  it "return degraded assemblies" do
    expect(@okay.degraded).to     eq([])
    expect(@degraded.degraded).to eq(['md0'])
  end

  it "returns components" do
    expect(@okay.getComponents('md0')).to eq(['sda1', 'sdb1'])
    expect(@okay.getComponents('md1')).to eq(['sda2', 'sdb2'])
    expect(@okay.getComponents('md99')).to be_nil
  end

  it "should return a human readable status" do
    expect(@okay.human).to          match RaidInfo::OkayPattern
    expect(@degraded.human).not_to  match RaidInfo::OkayPattern
    expect(@okay.human).not_to      match RaidInfo::DegradedPattern
    expect(@degraded.human).to      match RaidInfo::DegradedPattern
    expect(RaidInfo.new(mdBadFile).human).to match RaidInfo::NoRAID
  end
end


describe 'Get External Harddisk devices' do
devs_sbu =%(
---
- /dev/sdc1
- /dev/sdb6
- /dev/sdb5
- /dev/sdb4
- /dev/sdb3
- /dev/sdb2
- /dev/sdb1
- /dev/sda6
- /dev/sda5
- /dev/sda4
- /dev/sda3
- /dev/sda2
- /dev/sda1

)

devs_ng =%(
---
- /dev/sdc1
- /dev/sdb6
- /dev/sdb5
- /dev/sdb2
- /dev/sdb1
- /dev/sda3
- /dev/sda2
- /dev/sda1
)

  it "should work at niklaus giger place" do
    mounts_ng = YAML.load_file(File.join(File.dirname(__FILE__), "mounts.ng"))
    candidates = Sinatra::ElexisHelpers.getPossibleExternalDiskDrives(mounts_ng, YAML.load(devs_ng))
    fqdn = Socket.gethostbyname(Socket.gethostname).first
    if fqdn.match(/giger/i)
      puts "Okay: #{fqdn}"
      expect(candidates.size).to eq(2)
      expect(candidates['/dev/sdc']).not_to be_nil
      expect(candidates['/dev/sdd']).to     be_nil
    else
      puts "skip running niklaus: #{fqdn}"
    end
  end

  it "should work at peter schoenbucher place" do
    mounts_sbu = YAML.load_file(File.join(File.dirname(__FILE__), "mounts.sbu"))
    candidates = Sinatra::ElexisHelpers.getPossibleExternalDiskDrives(mounts_sbu, YAML.load(devs_sbu), mdstat_okay)
    expect(candidates.size).to eq(1)
    expect(candidates['/dev/sdc']).not_to be_nil
    expect(candidates['/dev/sdd']).to     be_nil
  end

end
