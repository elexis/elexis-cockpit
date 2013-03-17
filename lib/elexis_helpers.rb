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
include Sys

module Sinatra
  module ElexisHelpers
  Green  = '#66FF66'
  Red    = '#FF3300'
  Orange = '#FFA500'
  
  def get_hiera(key, default_value = nil)
    local_yaml_db   ||= ENV['COCKPIT_CONFIG']
    local_yaml_db   ||= File.join(File.dirname(File.dirname(__FILE__)), 'local_config.yaml')
    if File.exists?(local_yaml_db)
      config_values = YAML.load_file(local_yaml_db)
      value = config_values[key]
      puts "local config config for #{key} got #{value}" if $VERBOSE
    else
      hiera_yaml = '/etc/puppet/hiera.yaml'
      scope = 'path_to_no_file'
      value = Hiera.new(:config => hiera_yaml).lookup(key, 'unbekannt', scope)
      puts "#{hiera_yaml}: hiera key #{key} returns #{value}" 
    end
    value = default_value if default_value and not value
    value
  end
  
  # next function courtesy of 
  # http://stackoverflow.com/questions/10420352/converting-file-size-in-bytes-to-human-readable
  def getReadableFileSizeString(fileSizeInBytes)
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
  
  def get_db_backup_info(which_one)
    bkpInfo = Hash.new
    maxHours = 24
    maxDays  =  7
    search_path = get_hiera("::db::#{get_hiera('::db::type')}::backup::files")
    backups =  Dir.glob(search_path)
    bkpInfo[:backups] = backups
    if  bkpInfo[:backups].size == 0
      bkpInfo[:okay] = "Keine Backup_Dateien via '#{search_path}' gefunden"
      bkpInfo[:backup_tooltip] = "Fehlschlag. Bitte beheben Sie das Problem"
    else
      neueste = backups[0]
      modificationTime = File.mtime(neueste)
      human = distance_of_time_in_words(Time.now, modificationTime)
#        human = (Time.now - modificationTime).to_i
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
    bkpInfo[:dump_script] = get_hiera("::db::#{get_hiera('::db::type')}::dump::script")
    bkpInfo[:load_script] = get_hiera("::db::#{get_hiera('::db::type')}::load::script")
    bkpInfo[:bkp_files]   = get_hiera("::db::#{get_hiera('::db::type')}::backup::files")
    return bkpInfo
  end

  def getInstalledElexisVersions(elexisBasePaths = [ '/srv/elexis', '/usr/share/elexis', "#{ENV['HOME']}/elexis/bin" ])
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

  def getSizeOfMountPoint(mount_point)
    mp =  Filesystem.stat(mount_point)
    getReadableFileSizeString(mp.blocks * mp.block_size)
  end
  
  def getMountInfo(mounts = Hash.new)
    part_max_fill = 85  
    mount_points = Filesystem.mounts.select{|m| not /tmp|devpts|proc|sysfs|rootfs|pipefs|fuse|binfmt_misc/.match(m.mount_type) }
    mount_points.each do |m|
      mount_info = Hash.new
      mp =  Filesystem.stat(m.mount_point);
      percentage = 100-((mp.blocks_free.to_f/mp.blocks.to_f)*100).to_i 
      mount_info[:mount_point] = m.mount_point
      mount_info[:mount_type]  = m.mount_type
      mount_info[:percentage]  = percentage
      mount_info[:background]  = percentage < part_max_fill ? '#0a0' : '#FF0000'
      mount_info[:human_size]  = getSizeOfMountPoint(m.mount_point)
      mounts[m.mount_point]    = mount_info
    end
    mounts
  end

  def getDbConfiguration
    info = Hash.new
    info[:backup_server_is]  = get_hiera('::db::server::backup_server_is')
    info[:dbServer] = get_hiera('::db::server')
    info[:dbBackup] = get_hiera('::db::backup')
    info[:dbFlavors] = ['h2', 'mysql', 'postgresql' ]
    info[:dbHosts]  = [ 'localhost' ]
    info[:dbHosts] << :server if info[:server]
    info[:dbHosts] << 'backup' if info[:backup]
    info[:dbPorts]  = [ get_hiera('::db::port') ]
    info[:dbUsers]  = [ get_hiera('::db::user')]
    info[:dbNames]  = [ get_hiera('::db::main')]
    info
  end
  
  def getElexisVersionen
    elexisVarianten = Array.new
    elexisVariante = Hash.new
    elexisVariante[:name] = 'Medelexis 2.1.7'
    elexisVariante[:path] = 'http://www.medelexis.ch/dl21.php?file=medelexis-linux'
    elexisVarianten << elexisVariante
    elexisVariante = Hash.new
    elexisVariante[:name] = 'Elexis 2.1.6.1'   
    elexisVariante[:path] = 'http://ftp.medelexis.ch/downloads_opensource/elexis/2.1.6.1/elexis-linux-2.1.6.1.20111211-install.jar'
    elexisVarianten << elexisVariante
    elexisVarianten
  end

  def getBackupInfo
    backup = Hash.new 
    dbType = get_hiera("::db::type")
    return get_db_backup_info(dbType)
  end

  def getSystemInfo
    info          = getDbConfiguration
    info[:hostname] = Socket.gethostname
    info[:mounts] = getMountInfo
    info[:backup] = getBackupInfo
    info
  end
  
  AvoidBasicPoints = [ '/', '/home', '/usr', '/var', '/tmp', '/opt' ]
  def getPossibleExternalDiskDrives
    avoid = []
    Filesystem.mounts.each{ |x| 
                            if AvoidBasicPoints.index(x.mount_point)
                              next if /rootfs/.match(x.name)
                              File.symlink?(x.name) ? avoid << File.realpath(x.name).chop : avoid << x.name.chop 
                          end
                          }
    externals = Hash.new
    ((Dir.glob("/dev/sd??").collect{ |x| x.chop }.sort.uniq) - avoid).each {
      |mtPoint|
          mp =  Filesystem.stat(mtPoint);
          externals[mtPoint]  = getReadableFileSizeString(mp.blocks * mp.block_size * mp.fragment_size)
    }
    externals
  end
  
  end
  # this will only affect Sinatra::Application
  register ElexisHelpers
end
