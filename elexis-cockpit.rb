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

# from http://net.tutsplus.com/tutorials/ruby/singing-with-sinatra/
# HomePage http://www.sinatrarb.com/
# Abgesicherten Bereich https://github.com/integrity/sinatra-authorization
# ActiveRecord migrations: http://www.sinatrarb.com/faq.html#ar-migrations
# Add erubis for auto escaping HTML http://www.sinatrarb.com/faq.html#auto_escape_html
# Übersetzung: https://github.com/ai/r18n https://github.com/sinefunc/sinatra-i18n
# Beispiel unter https://github.com/ai/r18n/tree/master/sinatra-r18n
# Progressbar https://github.com/blueimp/jQuery-File-Upload
#  console: https://github.com/paul/progress_bar
# https://github.com/sinefunc/sinatra-support
# -percentage = (Time.now.to_i.modulo(500))/5
# %div.progress.progress-striped.active
#  %div.bar{:style => "width: #{percentage}%;"}
# http://samuelstern.wordpress.com/2012/11/28/making-a-simple-database-driven-website-with-sinatra-and-heroku/
# http://guides.rubyonrails.org/migrations.html
# http://ididitmyway.herokuapp.com/past/2010/4/18/using_active_record_in_the_console/
# https://github.com/janko-m/sinatra-activerecord
# Nächster Artikel ist sehr gut!
# http://danneu.com/posts/15-a-simple-blog-with-sinatra-and-active-record-some-useful-tools/
# https://github.com/zdennis/activerecord-import/wiki
# http://stackoverflow.com/questions/3704065/how-to-import-data-into-rails
# http://stackoverflow.com/questions/8476769/import-from-csv-into-ruby-array-with-1st-field-as-hash-key-then-lookup-a-field  
# Features: 
#  Freier Platz auf Festplatte auf lokalem Rechner
# Backup anstossen, 

# TODO: für Elexis-Cockpit
    # Freier Platz auf Festplatte (je Server und Backup)
    # Backup gelaufen (gestern, vorgestern), Zeit und Grösse, evtl. Änderungen plausibilisieren?
    # Backup in Test-DB einlesen
    # Backup auf externe Festplatte
    # Backup-Server online? à jour?
    # Neue (Med)Elexis-Version installieren, aktivieren, 
    # Auf alte Version zurückschalte
    # Dito für Linux, Mac/Windows unter Samba??
    # Artikelstamm/Tarmed (wann letztes Update). Aktuelleste Versionen?
# Später
    # Smartmonitor status
    # nagios
    # Updates von elexis-vagrant?
    # Display information about a particular filesystem.

require 'sinatra'  
require 'sinatra/base'
require 'data_mapper'
# require 'builder'
require 'redcloth'
require 'hiera'
require 'socket'
# to display human readable time difference
require 'action_view'
include ActionView::Helpers::DateHelper
require 'haml'

DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/demo.db")  

require File.join(File.dirname(__FILE__), 'lib', 'elexis_helpers')

class ElexisCockpit < Sinatra::Base
  register Sinatra::ElexisHelpers
  @batch = nil
  
  helpers do  
    include Rack::Utils  
    alias_method :h, :escape_html  
  end  

  configure do
    set :port,  9393 # same as shotgun
    set :info,  getSystemInfo
  end

  # Some helper links. Should allow use to easily get values from server/backup
  get '/info.yaml' do  
    getSystemInfo.to_yaml.gsub("\n",'<br>').gsub(' ', '&nbsp;')
  end

  get '/info.json' do  
    getSystemInfo.to_json.gsub("\n",'<br>').gsub(' ', '&nbsp;')
  end

  class BatchRunner
    attr_accessor :finished, :result, :endTime, :workThread, :updateThread
    attr_reader   :startTime, :batchFile, :title, :info
    $info = nil
    
    def initialize(batchFile, 
                  title="#{File.basename(batch_file)} ausführen",
                  okMsg="#{File.basename(batch_file)} erfolgreich beendet",
                  errMsg="#{File.basename(batch_file)} mit Fehler beendet",
                  info = nil)
      @title      = title
      @batchFile  = batchFile
      @finished   = false
      @okMsg      = "<div width='500px' style='background-color: #00FF00'  >#{okMsg}</div>"
      @errMsg     = "<div width='500px' style='background-color: #FF0000'  >#{errMsg}</div>"
      @info       = info
    end
    
    def runBatch
      # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
      unless @batchFile
        "<h1>Fehler beim Setup @batchFile ist nicht definiert! <h1>"
        return
      end
      back2home = "<p><a href='/'>Zurück zur Hauptseite</a></p>"
      if @batchFile.length < 2 or not File.exists?(@batchFile) or not File.executable?(@batchFile)
        "#{Time.now}: Fehler in der Konfiguration. Datei '#{@batchFile}' kann nicht ausgeführt werden" + back2home
      else
        @startTime = Time.now unless @startTime
        @workThread = Thread.new do
          @result = system(@batchFile)
          @endTime = Time.now
          @finished = true
        end if not @finished and not @workThread
        display = "<h3>#{@title}</h3>"
        if @finished
          diffSeconds = (@endTime-@startTime).to_i
          display += "<h3>Arbeit beendet (nach #{diffSeconds} Sekunden).</h3>"
          display += back2home 
          display += @result ? @okMsg : @errMsg
        else
          diffSeconds = (Time.now-@startTime).to_i
          display += "<h3>Arbeit ist seit #{diffSeconds} Sekunden am laufen.</h3>"
          display += "<p>Seite neu laden, um zu sehen, ob das Programm weiterhin läuft.</p>"
        end
        content = IO.read(@batchFile).gsub("\n", "<br>")
        display += "<p>Batchdatei '#{@batchFile}'. Startzeit #{@startTime}</p>"
        display += "<p>Inhalt der Batchdatei ist</p><p>#{content}</p>"
        @info ? display + @info.to_s : display
      end
    end
  end

  get '/' do
    @info = getSystemInfo
    settings.set(:info, @info)
    @title = 'Übersicht'
    settings.set(:batch, nil)
    haml :home
  end  

  get '/start' do
    @title = 'Elexis starten'
    @elexis_versions = getInstalledElexisVersions
    haml :start
  end

  post '/start' do
    puts "params = #{params.inspect}"
    version = params[:version]
    settings.set(:batch, nil)
    redirect "/runElexis?version=#{version}"
  end 

  get '/runElexis' do
    # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
    puts "#{request.path_info}: version #{params[:version]}"
    unless settings.batch
      cmd = "nice #{params[:version]}/elexis " # +
          # "-Dch.elexis.dbUser=#{params[:dbUser]} -Dch.elexis.dbPw=#{params[:dbPw]} " +
          # "-Dch.elexis.dbFlavor=#{params[:dbFlavor]}  -Dch.elexis.dbSpec=jdbc:#{params[:dbFlavor]}://#{params[:dbHost]}:#{params[:dbPort]}/#{params[:dbName]}"
      # Could also query for -Dch.elexis.username=test -Dch.elexis.password=test 
      file = Tempfile.new('runElexis')
      file.puts("#!/bin/bash -v")
      file.puts(cmd + " &") # run in the background
      file.close
      File.chmod(0755, file.path)
      settings.batch = BatchRunner.new(file.path, 
                                        'Elexis starten',
                                        'Elexis erfolgreich gestartet',
                                        'Elexis konnte nicht gestartet werde')
    end
    @title = settings.batch.title
    settings.batch.runBatch
  end

  get '/runDbBackup' do
    puts "get #{__LINE__}: #{request.path_info}: params #{params}.inspect"
    unless settings.info[:backup][:dump_script]
      "<h3>Fehler im Setup. Kein backup-Script definiert</h3>"
      redirect '/'
    end
    # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
    unless settings.batch
      settings.batch = BatchRunner.new(settings.info[:backup][:dump_script], 
                                        'Datenbank-Sicherung gestartet',
                                        'Datenbank-Sicherung erfolgreich beendet',
                                        'Datenbank-Sicherung fehlgeschlagen!!!')
    end
    @title = settings.batch.title
    settings.batch.runBatch
  end

  post '/runDbBackup' do
    puts "get #{__LINE__}: #{request.path_info}: params #{params}.inspect"
    settings.set(:batch, nil)
    redirect '/runDbBackup'    
  end 

  get '/formatEncrypted' do
    puts "get #{__LINE__}: #{request.path_info}: params #{params}.inspect"
    @title = 'Verschlüsselte Partition erstellen'
    @candidates = Hash.new
    @candidates = getPossibleExternalDiskDrives
    haml :formatEncrypted
  end  
  
  post '/runFormatting' do
    puts "get #{__LINE__}: #{request.path_info}: params #{params}.inspect"
    device = params[:device]
    settings.set(:batch, nil)
    redirect "/runFormatting?device=#{device}"
  end  # start the server if ruby file executed directly
  
  get '/runFormatting' do
    puts "get #{__LINE__}: #{request.path_info}: params #{params}.inspect"
    # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
    unless settings.batch
      cmd = "#{get_hiera('::hd::external::format_and_encrypt')} -init --device #{params[:device]}"  
      file = Tempfile.new('runFormatting')
      file.puts("#!/bin/bash -v")
      file.puts(cmd) # Wait till finished
      file.close
      File.chmod(0755, file.path)
      settings.batch = BatchRunner.new(file.path, 
                                        'Externe Festplatte formattieren und verschlüsseln',
                                        'Externe Festplatte erfolgreich verschlüsselt',
                                        'Externe Festplatte konnte nicht formattieren werden')
    end
    @title = settings.batch.title
    settings.batch.runBatch
  end  # start the server if ruby file executed directly
  
  get '/loadDatabase' do
    haml :loadDatabase
  end
  
  post "/loadDatabase" do 
    puts "#{request.path_info}: params #{params}"
    dumpFile = 'uploads/' + params['dumpFile'][:filename]
    tempFile = params['dumpFile'][:tempfile]
    puts tempFile
    puts File.exists?(tempFile)
    puts File.size(tempFile)
    puts tempFile.inspect
    settings.set(:batch, nil)
    redirect "/runLoadDatabase?dumpFile=#{tempFile.path}"
  end

  post '/runLoadDatabase' do
    puts "#{request.path_info}: params #{params}"
    dumpFile = params[:dumpFile]
    settings.set(:batch, nil)
    redirect "/runLoadDatabase?dumpFile=#{dumpFile}"
  end
  
  get '/runLoadDatabase' do
    puts "get #{__LINE__}: #{request.path_info}: params #{params}.inspect"
    # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
    unless settings.batch
      settings.batch = BatchRunner.new(settings.info[:backup][:load_script],
                                        'Datenbank aus Dump wieder herstellen',
                                        'Datenbank erfolgreich wieder hergestellt',
                                        'Datenbank konnte nicht wieder hergestellt werden')
    end
    @title = settings.batch.title
    settings.batch.runBatch
  end  # start the server if ruby file executed directly
 
  get '/installElexis' do
    puts "get 1 #{request.path_info}: params #{params}"
    haml :installElexis
  end
  
  post '/runInstallElexis' do
    puts "post #{request.path_info}: params #{params}"
    url = params[:url]
    settings.set(:batch, nil)
    redirect "/runInstallElexis?url=#{url}"
  end
  
  get '/runInstallElexis' do
    puts "get #{__LINE__}: #{request.path_info}: params #{params}.inspect"
    puts "get #{__LINE__}: #{request.path_info}: params #{settings.batch}.inspect"

    # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
    unless settings.batch
      cmd = "#{get_hiera('::elexis::install::script')} #{params[:url]} "  
      settings.set(:batch, nil)
      file = Tempfile.new('installElexis')
      file.puts("#!/bin/bash -v")
      file.puts(cmd) # Wait till finished
      file.close
      File.chmod(0755, file.path)
      settings.batch = BatchRunner.new(file.path, 
                                        'Elexis-Version installieren',
                                        'Elexis-Version installiert',
                                        'Fehler bei der Installation von Elexis')
    end
    @title = settings.batch.title
    settings.batch.runBatch
  end 
  
  get '/switchDbServer' do
    puts "get 1 #{request.path_info}: params #{params}"
    haml :switchDbServer
  end
  
  post '/runSwitchDbServer' do
    puts "post #{request.path_info}: params #{params}"
    url = params[:url]
    settings.set(:batch, nil)
    redirect "/runSwitchDbServer?url=#{url}"
  end
  
  get '/runSwitchDbServer' do
    # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
    puts "get #{__LINE__}: #{request.path_info}: params #{params}.inspect"
    puts "get #{__LINE__}: #{request.path_info}: params #{settings.batch}.inspect"

    unless settings.batch
      script_key = "::db::#{get_hiera("::db::type")}::switch::script"
      script_name = get_hiera(script_key)
      settings.batch = BatchRunner.new(script_name,
                                        'Elexis-Datenbank Server umschalten',
                                        'Elexis-Datenbank Server umgeschalten',
                                        'Fehler beim Umschalten des Elexis-Datenbank Servers')
    end
    @title = settings.batch.title
    settings.batch.runBatch
  end 

  
  get '/backup2external' do
    puts "get 1 #{request.path_info}: params #{params}"
    haml :backup2external
  end
  
  post '/runBackup2external' do
    puts "post #{request.path_info}: params #{params}"
    settings.set(:batch, nil)
    redirect "/runBackup2external"
  end

  get '/runBackup2external' do
    # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
    puts "get #{__LINE__}: #{request.path_info}: params #{params}.inspect"
    puts "get #{__LINE__}: #{request.path_info}: params #{settings.batch}.inspect"

    # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
    unless settings.batch
      cmd = "#{get_hiera('::hd::external::format_and_encrypt')} --keyfile #{get_hiera('::hd::external::keyfile')}"      
      settings.set(:batch, nil)
      file = Tempfile.new('bkp2ext')
      file.puts("#!/bin/bash -v")
      file.puts(cmd) # Wait till finished
      file.close
      File.chmod(0755, file.path)
      settings.batch = BatchRunner.new(file.path, 
                                        'Backup auf verschlüsselte externe Festplatte',
                                        'Backup auf verschlüsselte externe Festplatte erfolgreich',
                                        'Fehler beim Backup auf verschlüsselte externe Festplatte')
    end
    @title = settings.batch.title
    settings.batch.runBatch
  end 
  
  # start the server if ruby file executed directly
  run! if app_file == $0
end
