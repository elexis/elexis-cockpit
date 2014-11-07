#!/usr/bin/env ruby
# encoding: utf-8
# Elexis-Cockpit. Eine kleine auf sinatra basierend Applikation
# um Wartungarbeiten für Elexis einfach auszuführen.
#
# Copyright (C) 2013 Niklaus Giger <niklaus.giger@member.fsf.org>
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software Foundation,
#  Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA

require 'sys/filesystem'
require 'open-uri'
include Sys

module Sinatra
  module ElexisHelpers
  Green  = '#66FF66'
  Red    = '#FF3300'
  Orange = '#FFA500'
  White  = '#ffffff'
  Versions_URL = 'http://ngiger.dyndns.org/elexis/elexisVersions.yaml'

  # please keep get_elexis_default in sync with elexis::params!
  @@db_type = nil
  attr_reader :value
  def self.get_elexis_default(key)
    case key
      when "elexis::params::db_type"
        @@db_type = 'mysql'
        return @@db_type
      when "elexis::params::db_main"
        return 'elexis'
      when "elexis::params::db_test"
        return 'test'
      when /elexis.*_backup_files$/
        if @@db_type == 'mysql'
          return "/opt/backup/mysql/*/elexis.dump*.gz"
        else
          return "/opt/backup/pg/*/pg_backup_*.sql"
        end
      when 'elexis::params::db_server'
        return 'server'
      when 'elexis::params::db_backup'
        return 'backup'
      when 'elexis::params::db_user'
        return 'elexis'
      when 'elexis::params::db_server::backup_server_is'
        return 'backup'
      when 'elexis::params::db_port'
        return 'db_port_default'
      default
        return nil
    end
  end

  def self.get_hiera(key, default_value = nil)
    local_yaml_db   ||= ENV['COCKPIT_CONFIG']
    local_yaml_db   ||= File.join(File.dirname(File.dirname(__FILE__)), 'local_config.yaml')
    if File.exists?(local_yaml_db)
      config_values = YAML.load_file(local_yaml_db)
      value = config_values[key]
      puts "local config #{local_yaml_db} for #{key} got #{value}" if $VERBOSE
    else
      hiera_yaml = '/etc/hiera.yaml'
      scope = '/dev/null'
      value = Hiera.new(:config => hiera_yaml).lookup(key, nil, scope)
      puts "#{hiera_yaml}: hiera key #{key} returns #{value}" if $VERBOSE
    end
    value ||= get_elexis_default(key)
    puts "#{hiera_yaml} #{__LINE__}: hiera key #{key} default: #{default_value}" unless value
    value ||= default_value
    value
  end

  # next function courtesy of
  # http://stackoverflow.com/questions/10420352/converting-file-size-in-bytes-to-human-readable
  def self.getReadableFileSizeString(fileSizeInBytes)
      i = -1;
      byteUnits = [' kB', ' MB', ' GB', ' TB', 'PB', 'EB', 'ZB', 'YB']
      while true do
          fileSizeInBytes = fileSizeInBytes / 1024
          i += 1
          break if (fileSizeInBytes <= 1024)
        end

#      return Math.max(fileSizeInBytes, 0.1).toFixed(1) + byteUnits[i]
      return (fileSizeInBytes > 0.1 ? fileSizeInBytes.to_s : 1.to_s)+ byteUnits[i]
  end

  def self.distance_of_time_in_words_to_now(time)
    if defined?(ActionView::Helpers::DateHelper.distance_of_time_in_words_to_now)
      return ActionView::Helpers::DateHelper.distance_of_time_in_words_to_now(time)
    else
      human = (Time.now - time).to_i.to_s + ' Sekunden'
    end
  end

  def self.distance_of_time_in_words(later, older)
    if defined?(ActionView::Helpers::DateHelper.distance_of_time_in_words)
      return ActionView::Helpers::DateHelper.distance_of_time_in_words(later, older)
    else
      human = (later - older).to_i.to_s + ' Sekunden'
    end
  end

  def self.get_db_backup_info(which_one)
    bkpInfo = Hash.new
    maxHours = 24
    maxDays  =  7
    db_type = get_hiera('elexis::params::db_type', 'mysql')
    puts "db_type ist #{db_type}"
    search_path = get_hiera("elexis::#{db_type}_backup_files")
    puts "search_path ist #{search_path}"
    backups =  search_path ? Dir.glob(search_path) : []
    if backups.size == 0 # try default value
      search_path2 = "/opt/backup/#{db_type}/*/elexis.dump*.gz"
      puts "search_path2 ist #{search_path2}"
      backups =  Dir.glob(search_path2)
    end
    bkpInfo[:backups] = backups
    if  bkpInfo[:backups].size == 0
      bkpInfo[:backups] = backups
      bkpInfo[:colour] = Red
      bkpInfo[:okay] = "Keine Backup_Dateien via '#{search_path}' oder '#{search_path2}' gefunden"
      bkpInfo[:backup_tooltip] = "Fehlschlag. Bitte beheben Sie das Problem"
    else
      neueste = backups[0]
      modificationTime = File.mtime(neueste)
      human = self.distance_of_time_in_words(Time.now, modificationTime)
      if ((Time.now - modificationTime) > maxDays*24*60*60)
        bkpInfo[:okay] = "Neueste Backup-Datei '#{neueste}' erstellt vor #{human} ist älter als #{maxDays} Tage"
        bkpInfo[:backup_tooltip] = "Fehlschlag. Fand #{backups.size} Backup-Dateien via '#{search_path}'"
      elsif ((Time.now - modificationTime) > maxHours*60*60)
        bkpInfo[:colour] = Orange
        bkpInfo[:okay] = "Neueste Backup-Datei '#{neueste}' erstellt vor #{human} ist älter als #{maxHours} Stunden!"
        bkpInfo[:backup_tooltip] = "Fehlschlag. Fand #{backups.size} Backup-Dateien via '#{search_path}'"
      else
        bkpInfo[:colour] = Green
        bkpInfo[:okay]  = "#{which_one.capitalize}-Backup okay"
        bkpInfo[:backup_tooltip] = "#{backups.size} Backups vorhanden. Neueste #{neueste}  #{File.size(neueste)} Bytes erstellt vor #{human}"
      end
    end
    bkpPrefix = "/usr/local/bin/#{db_type}"
    mainDb    = Sinatra::ElexisHelpers.get_hiera("elexis::params::db_main")
    testDb    = Sinatra::ElexisHelpers.get_hiera("elexis::params::db_test")
    bkpInfo[:dump_script] = "#{bkpPrefix}_dump_#{mainDb}.rb"
    bkpInfo[:load_main]   = "#{bkpPrefix}_load_#{mainDb}_db.rb"
    bkpInfo[:load_test]   = "#{bkpPrefix}_load_#{testDb}_db.rb"
    bkpInfo[:bkp_files]   = get_hiera("elexis::#{get_hiera('elexis::params::db_type')}_backup_files")
    return bkpInfo
  end

  def self.getInstalledElexisVersions(elexisBasePaths = [ '/srv/elexis', '/usr/share/elexis', "#{ENV['HOME']}/elexis/bin", '/opt/elexis', '/opt/elexis_opensource' ])
    versions = Hash.new
    elexisBasePaths.each{
      |path|
        search_path = "#{path}/*/elexis"
        puts "#{path}: search_path ist #{search_path}"
        iniFiles = Dir.glob(search_path)
        puts iniFiles
        iniFiles.each{
          |iniFile|
            version  = File.basename(File.dirname(iniFile))  # .sub(/elexis-/, ''))
            puts "#{iniFile} version #{version}"
            versions[version] = File.dirname(iniFile) unless versions[version]
                    }
    }
    versions.sort.reverse
  end

  def self.getSizeOfMountPoint(mount_point)
    mp =  Filesystem.stat(mount_point)
    getReadableFileSizeString(mp.blocks * mp.block_size)
  end

  def self.getMountInfo(mounts = Hash.new)
    part_max_fill = 85
    mount_points = Filesystem.mounts.select{|m| not /tmp|devpts|proc|sysfs|rootfs|pipefs|fuse|binfmt_misc/.match(m.mount_type) }
    mount_points.each do |m|
      mount_info = Hash.new
      begin
        mp =  Filesystem.stat(m.mount_point);
        next if mp.blocks_available == 0
        percentage = 100-((mp.blocks_free.to_f/mp.blocks.to_f)*100).to_i
        mount_info[:mount_point] = m.mount_point
        mount_info[:mount_type]  = m.mount_type
        mount_info[:percentage]  = percentage
        mount_info[:background]  = percentage < part_max_fill ? '#0a0' : '#FF0000'
        mount_info[:human_size]  = getSizeOfMountPoint(m.mount_point)
        mounts[m.mount_point]    = mount_info
      rescue
        puts "Failed getting info for #{m.mount_point}. Continue with next"
      end
    end
    mounts
  end

  def self.getDbConfiguration
    info = Hash.new
    info[:backup_server_is]  = get_hiera('elexis::params::db_server::backup_server_is')
    info[:dbServer] = get_hiera('elexis::params::db_server')
    info[:dbBackup] = get_hiera('elexis::params::db_backup')
    info[:dbFlavors] = ['h2', 'mysql', 'postgresql' ]
    info[:dbHosts]  = [ 'localhost' ]
    info[:dbHosts] << :server if info[:server]
    info[:dbHosts] << 'backup' if info[:backup]
    info[:dbPorts]  = [ get_hiera('elexis::params::db_port') ]
    info[:dbUsers]  = [ get_hiera('elexis::params::db_user')]
    info[:dbNames]  = [ get_hiera('elexis::params::db_main')]
    info
  end

  def self.getElexisVersionen
    begin
      elexisVarianten = YAML::load_documents( open(Versions_URL))[0]
    rescue
      urlName = File.join(File.dirname(File.dirname(__FILE__)), 'elexisVersions.yaml')
      elexisVarianten =  YAML::load( File.open(urlName) )
    end
    elexisVarianten
  end

  def self.getBackupInfo
    backup = Hash.new
    dbType = get_hiera("elexis::params::db_type")
    return get_db_backup_info(dbType)
  end

  def self.getSystemInfo
    info          = getDbConfiguration
    info[:hostname] = Socket.gethostname
    info[:mounts] = getMountInfo
    info[:backup] = getBackupInfo
    info[:raid]   = RaidInfo.new()
    info
  end

  AvoidBasicPoints = [ '/', '/home', '/usr', '/var', '/tmp', '/opt' ]
  def self.getPossibleExternalDiskDrives(injectMounts = nil, injectDevices = nil, injectMdStat = nil)
    avoid = []
    mounts = injectMounts ? injectMounts : Filesystem.mounts
    mounts.each{ |x|
                            if AvoidBasicPoints.index(x.mount_point)
                              next if /rootfs/.match(x.name)
                              File.symlink?(x.name) ? avoid << File.realpath(x.name).chop : avoid << x.name.chop
                          end
                          }
    externals = Hash.new
    devices = injectDevices ? injectDevices : Dir.glob("/dev/sd??")
    mdStat  = injectMdStat ? RaidInfo.new(RaidInfo::MdStat, injectMdStat) : RaidInfo.new
    mdComponents = nil
    mdComponents = mdStat.components.each.collect{ |x,y| y }.flatten.sort if mdStat and mdStat.components
    chopped = mdComponents ?  mdComponents.each{ |deviceName| deviceName.chop! }.sort!.uniq! : nil
    ((devices.collect{ |x| x.chop }.sort.uniq) - avoid).each {
      |mtPoint|
          if injectMounts
            externals[mtPoint]  = 'injected: '+ mtPoint
          else
            mp =  Filesystem.stat(mtPoint);
            externals[mtPoint]  = getReadableFileSizeString(mp.blocks * mp.block_size * mp.fragment_size)
          end
          if mdStat
            short = mtPoint.split('/')[-1]
            externals.delete(mtPoint) if chopped and chopped.index(mtPoint.split('/')[-1])
    end
    }
    externals
  end

  @crossRef = Hash.new

  def self.setRunnerForPath(path, runner)
    @crossRef = Hash.new unless defined?(@crossRef)
    @crossRef[path] = runner
    puts "#{__LINE__}: #{@crossRef.inspect}" if $VERBOSE
  end

  def self.getRunnerForPath(path)
    puts "#{__LINE__}: #{@crossRef.inspect}" if $VERBOSE
    @crossRef[path]
  end

    # Supports only Linux md via /proc/mdstat!
    # see https://raid.wiki.kernel.org/index.php/Mdstat
    class RaidInfo
      MdStat = '/proc/mdstat'
      MatchAssemblyOfTwo = /^(\w*)\W*\:\W*(\w*)\W*(\w*)\W*(\w*)\[\d*\]\W*(\w*)\[\d*\]/
      MatchConfig = /\[([_U]*)\]/
      OkayPattern = /Alle RAID.*okay/
      DegradedPattern = /degraded/
      NoRAID          = 'Kein RAID Festplatten gefunden'

      attr_reader :degraded, :active, :raw, :components, :background_colour

      def human
        return NoRAID unless @raw
        msg  = "RAID-Partitionen #{@components.collect{ |x,y| x}.inspect}: "
        msg += @degraded.size > 0 ? "Warnung: haben schlechte Festplatten in #{@degraded.join(' ')} (degraded)" :
              "Alle RAID okay"
      end

      def initialize(mdStatFile = MdStat, content = nil)
        if content == nil
          @raw = IO.read(mdStatFile) if File.exists?(mdStatFile)
        else
          @raw = content
        end
        @background_colour = White
        return unless @raw
        @active = Array.new
        @degraded = Array.new
        @components = Hash.new
        current = nil
        @raw.split("\n").each {
          |line|
          next if /^Personalities|^unused/.match(line)
          if m = MatchAssemblyOfTwo.match(line)
            if m[2].eql?('active')
              @active << m[1]
              current = m[1]
              @components[m[1].clone] = Array.new
              name1 = m[4]
              name2 = m[5]
              @components[m[1]] << name1
              @components[m[1]] << name2
            end
          elsif m = MatchConfig.match(line)
            @degraded << current if /_/.match(m[1])
          end
        }
          @background_colour = Orange if @degraded.size > 0
      end

      def getComponents(mdpartition)
        @components ? @components[mdpartition] : nil
      end

    end
  end


  # Skip registering when running as sinatra app
  if defined?(register)
    # this will only affect Sinatra::Application
    register ElexisHelpers
  end

end
