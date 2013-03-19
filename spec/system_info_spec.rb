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
    RaidInfo.new(mdBadFile).active.should be_nil
    RaidInfo.new(mdBadFile).degraded.should be_nil
    RaidInfo.new(mdBadFile).getComponents('x').should be_nil
  end
  
  it "should return raw info" do
    @okay.raw.should == mdstat_okay
  end
  
  it "return active assemblies" do
    @okay.active.should     == [ 'md0', 'md1' ]
    @degraded.active.should == [ 'md0', 'md1' ]
  end
    
  it "return degraded assemblies" do
    @okay.degraded.should     == []
    @degraded.degraded.should == ['md0']
  end

  it "returns components" do
    @okay.getComponents('md0').should == ['sda1', 'sdb1']
    @okay.getComponents('md1').should == ['sda2', 'sdb2']
    @okay.getComponents('md99').should be_nil
  end
  
  it "should return a human readable status" do
    @okay.human.should          match RaidInfo::OkayPattern
    @degraded.human.should_not  match RaidInfo::OkayPattern
    @okay.human.should_not      match RaidInfo::DegradedPattern
    @degraded.human.should      match RaidInfo::DegradedPattern
    RaidInfo.new(mdBadFile).human.should match RaidInfo::NoRAID
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
    candidates.size.should == 1
    candidates['/dev/sdc'].should_not be_nil
    candidates['/dev/sdd'].should     be_nil
  end
  
  it "should work at a special candidates" do
    candidates = Sinatra::ElexisHelpers.getPossibleExternalDiskDrives
    candidates.size.should == 1
    candidates['/dev/sdc'].should_not be_nil
    candidates['/dev/sdd'].should     be_nil
  end if Socket.gethostname.eql?('ng-tr')

  it "should work at peter schoenbucher place" do
    mounts_sbu = YAML.load_file(File.join(File.dirname(__FILE__), "mounts.sbu"))
    candidates = Sinatra::ElexisHelpers.getPossibleExternalDiskDrives(mounts_sbu, YAML.load(devs_sbu), mdstat_okay)
    candidates.size.should == 1
    candidates['/dev/sdc'].should_not be_nil
    candidates['/dev/sdd'].should     be_nil
  end

end
