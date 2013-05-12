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
# require 'action_view'
# include ActionView::Helpers::DateHelper
require 'haml'

DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/demo.db")  

require File.join(File.dirname(__FILE__), 'lib', 'elexis_helpers')

class ElexisCockpit < Sinatra::Base
  register Sinatra::ElexisHelpers
  @batch = nil
  
  helpers do  
    include Rack::Utils  
    alias_method :h, :escape_html  
    def title(str = nil)
      # helper for formatting your title string
      if str
        str + ' | Site'
      else
        'Site'
      end
    end
  end  

 class BatchRunner
    attr_accessor :finished, :result, :endTime, :workThread, :updateThread
    attr_reader   :startTime, :batchFile, :title, :info
    $info = nil
    $back2home = "<p><a href='/'>Zurück zur Hauptseite</a></p>"
    
    def initialize(batchFile, 
                  title="#{File.basename(batch_file)} ausführen",
                  okMsg="#{File.basename(batch_file)} erfolgreich beendet",
                  errMsg="#{File.basename(batch_file)} mit Fehler beendet",
                  info = nil)
      @title      = title
      if batchFile
        @batchFile  =  batchFile.split(' ')[0]
        @batchParams = batchFile.split(' ').size == 1 ? nil : batchFile.split(' ')[1..-1]
        puts "running #{@batchFile} params #{@batchParams}"
      else
        @batchFile  =  "unknown batch file"
      end
      @finished   = false
      @okMsg      = "<div width='500px' style='background-color: #00FF00'  >#{okMsg}</div>"
      @errMsg     = "<div width='500px' style='background-color: #FF0000'  >#{errMsg}</div>"
      @info       = info
    end
    
    def createPages(context, name)
      runnerName = '/run_'+name
      puts "createPages #{runnerName} batch #{@batchFile}"
      @batchInfo = nil
      puts (self.methods - Object.methods).inspect
      Sinatra::ElexisHelpers.setRunnerForPath(runnerName, self.clone)
      
      context.get '/'+name do
        puts "get #{__LINE__}: #{request.path_info}: params #{params}.inspect"
        haml name
      end
      
      context.post runnerName do
        puts "line #{__LINE__}: post #{__LINE__}: #{request.path_info}: params #{params}.inspect"
        settings.set(:batch, nil)
        redirect runnerName
      end

      context.get runnerName do
        # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
        puts "get #{__LINE__}: #{request.path_info}: params #{params}.inspect"
        puts "get #{__LINE__}: #{request.path_info}: getRunnerForPath #{Sinatra::ElexisHelpers.getRunnerForPath(request.path_info)}.inspect"
        
        # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
        unless settings.batch
          cmd = "#{@batchFile} #{@batchParams}"
          puts "runnerName #{runnerName} cmd #{cmd} @batchFile #{@batchFile}"
          if defined?(cmd)
            file = Tempfile.new(name)
            file.puts("#!/bin/bash -v")
            file.puts(cmd) # Wait till finished
            file.close
            File.chmod(0755, file.path)
          end
          settings.set(:batch, Sinatra::ElexisHelpers.getRunnerForPath(request.path_info))
        end
        @title = self.title
        settings.batch.runBatch
      end 

    end
    
    def runBatch
      # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
      unless @batchFile
        "<h1>Fehler beim Setup @batchFile ist nicht definiert! <h1>"
        return
      end
      if @batchFile.length < 2 or not File.exists?(@batchFile) or not File.executable?(@batchFile)
        "#{Time.now}: Fehler in der Konfiguration. Datei '#{@batchFile}' kann nicht ausgeführt werden" + $back2home
      else
        cmd = @batchFile
        cmd += " #{@batchParams.join(' ')}" if @batchParams
        @startTime = Time.now unless @startTime
        @workThread = Thread.new do
          begin
            puts "running #{cmd}"
            @result = system(cmd)
            puts "#{cmd} returned #{@result}"
          rescue
            puts "rescue for #{cmd}"
            @result = false
          end
          @endTime = Time.now
          @finished = true
        end if not @finished and not @workThread
        display = "<h3>#{@title}</h3>"
        if @finished
          diffSeconds = (@endTime-@startTime).to_i
          display += "<h3>Arbeit beendet (nach #{diffSeconds} Sekunden).</h3>"
          display += $back2home 
          display += @result ? @okMsg : @errMsg
        else
          diffSeconds = (Time.now-@startTime).to_i
          display += "<h3>Arbeit ist seit #{diffSeconds} Sekunden am laufen.</h3>"
          display += "<p>Seite neu laden, um zu sehen, ob das Programm weiterhin läuft.</p>"
        end
        content = 'unbekannt. Wahrscheinlich eine Exe-Datei.'
        begin
          content = IO.read(@batchFile).gsub("\n", "<br>")
        rescue
        end
        display += "<p>Befehl: '#{cmd} '</p>"
        display += "<p>Startzeit: #{@startTime}</p>"
        display += "<p>Inhalt der Batchdatei ist</p><p>#{content}</p>"
        @info ? display + @info.to_s : display
      end
    end
  end

  configure do
    set :port,  9393 # same as shotgun
    set :info,  Sinatra::ElexisHelpers.getSystemInfo
    set :bind, '0.0.0.0' # open it on all network interfaces
  end

  # Some helper links. Should allow use to easily get values from server/backup
  get '/info.yaml' do  
    getSystemInfo.to_yaml.gsub("\n",'<br>').gsub(' ', '&nbsp;')
  end

  get '/info.json' do  
    getSystemInfo.to_json.gsub("\n",'<br>').gsub(' ', '&nbsp;')
  end

  get '/' do
    @info = Sinatra::ElexisHelpers.getSystemInfo
    settings.set(:info, @info)
    @title = 'Übersicht'
    settings.set(:batch, nil)
    haml :home
  end  
  
  get '/info' do
    haml :info
  end
  
  get '/danke' do
    haml :danke
  end

  get '/todo' do
    haml :todo
  end
  
  get '/error' do
    haml :error
  end
  
  get '/startElexis' do
    @title = 'Elexis starten'
    @elexis_versions = Sinatra::ElexisHelpers.getInstalledElexisVersions
    puts "#{request.path_info}: line #{__LINE__}: version #{params[:version]}"
    haml :startElexis
  end

  post '/run_startElexis' do
    puts "line #{__LINE__}: post #{request.path_info}: params #{params}"
    query = params.map{|key, value| "#{key}=#{value}"}.join("&")
    settings.set(:batch, nil) 
    redirect "/run_startElexis?#{query}"
  end 

  get '/run_startElexis' do
    # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
    puts "#{request.path_info}: line #{__LINE__}: version #{params[:version]}"
    flavor = params[:dbFlavor]
    flavor = 'postgresql' if /pg/i.match(flavor)
    dbHost = 'localhost' 
    unless settings.batch
      cmd = "DISPLAY=:0 nice #{params[:version]}/elexis -vmargs "  +
           "-Dch.elexis.dbUser=#{params[:dbUser]} -Dch.elexis.dbPw=#{params[:dbPw]} " +
           "-Dch.elexis.dbFlavor=#{flavor} -Dch.elexis.dbSpec=jdbc:#{flavor}://#{dbHost}/#{params[:dbName]}"
      # -Dch.elexis.dbSpec=jdbc:#{params[:dbFlavor]}://#{params[:dbHost]}:#{params[:dbPort]}/#{params[:dbName]}"
      # Could also query for -Dch.elexis.username=test -Dch.elexis.password=test 
     # eg. jdbc:mysql://localhost:3306/elexis
      cmd = File.join(File.dirname(__FILE__), "mock_scripts", "start.rb") if   ENV['RUNNING_WATIR_TEST']
      puts "#{request.path_info}: line #{__LINE__}: cmd #{cmd}"
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

  dbBackup = BatchRunner.new(settings.info[:backup][:dump_script], 
                            'Datenbank-Sicherung gestartet',
                            'Datenbank-Sicherung erfolgreich beendet',
                            'Datenbank-Sicherung fehlgeschlagen!!!')
  dbBackup.createPages(self, 'dbBackup')
  
  get '/formatEncrypted' do
    puts "get #{__LINE__}: #{request.path_info}: params #{params}.inspect"
    @title = 'Verschlüsselte Partition erstellen'
    @candidates = Hash.new
    @candidates = Sinatra::ElexisHelpers.getPossibleExternalDiskDrives
    haml :formatEncrypted
  end  
  
  post '/run_formatting' do
    puts "get #{__LINE__}: #{request.path_info}: params #{params}.inspect"
    device = params[:device]
    settings.set(:batch, nil)
    redirect "/run_formatting?device=#{device}"
  end  # start the server if ruby file executed directly
  
  get '/run_formatting' do
    puts "get #{__LINE__}: #{request.path_info}: params #{params}.inspect"
    # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
    unless settings.batch
      cmd = "#{Sinatra::ElexisHelpers.get_hiera('elexis::hd_external_format_and_encrypt')} -init --device #{params[:device]}"  
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
  
  post '/loadDatabase' do 
    puts "#{request.path_info}: line #{__LINE__}: params #{params.inspect}"
    # dumpFile = 'uploads/' + params['dumpFile'][:filename]
    unless params['dumpFile'] and params['dumpFile'].size > 0 and File.exists?(params['dumpFile'])
      $errorMsg = "#{Time.now}: Fehler: Eine Datei zum laden muss ausgewählt werden!"
      redirect '/error'
    else
      dumpFile = params['dumpFile'][:tempfile].path
      puts "#{request.path_info}: dumpFile #{dumpFile} exists? #{File.exists?(dumpFile)} size #{File.size(dumpFile)}"
      settings.set(:batch, nil)
      puts "#{request.path_info}: line #{__LINE__}: params #{params}"
      redirectUrl =  "/run_loadDatabase?whichDb=#{params[:whichDb]}&dumpFile=#{dumpFile}"
      redirect redirectUrl
    end
  end

  get '/loadTestDatabase' do
    haml :loadTestDatabase
  end
  
  post '/loadTestDatabase' do 
    puts "#{request.path_info}: line #{__LINE__}: params #{params}"
    # dumpFile = 'uploads/' + params['dumpFile'][:filename]
    unless params['dumpFile'] 
      $errorMsg =  "#{Time.now}: Fehler: Eine Datei zum laden muss ausgewählt werden!"
      redirect '/error'
    else
      dumpFile = params['dumpFile'][:tempfile].path
      puts "#{request.path_info}: dumpFile #{dumpFile} exists? #{File.exists?(dumpFile)} size #{File.size(dumpFile)}"
      settings.set(:batch, nil)
      puts "#{request.path_info}: line #{__LINE__}: params #{params}"
      redirectUrl =  "/run_loadDatabase?whichDb=#{params[:whichDb]}&dumpFile=#{dumpFile}"
      redirect redirectUrl
    end
  end

  post '/run_loadDatabase' do
    puts "line #{__LINE__}: post #{request.path_info}: params #{params}"
    query = params.map{|key, value| "#{key}=#{value}"}.join("&")
    settings.set(:batch, nil)
    redirect "/run_loadDatabase?#{query}"
  end
  
  get '/run_loadDatabase' do
    puts "get #{__LINE__}: #{request.path_info}: params 0"
    puts "get #{__LINE__}: #{request.path_info}: params #{params.inspect}"
    puts "get #{__LINE__}: #{params[:dumpFile].inspect}"
    # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
    whichDb = params[:whichDb]
    dumpFile = params[:dumpFile]
    loadScript = "/usr/local/bin/#{Sinatra::ElexisHelpers.get_hiera("elexis::db_type")}_load_#{whichDb}_db.rb"
    if not File.exists?(loadScript) 
      $errorMsg =  "#{Time.now}: Fehler in der Konfiguration. Script #{loadScript} nicht vorhanden"
      redirect '/error'
    elsif not File.exists?(dumpFile)
      $errorMsg =  "#{Time.now}: Fehler dumpFile #{dumpFile} nicht vorhanden"
      redirect '/error'
    else
      cmd = "#{loadScript} #{dumpFile}"  
      file = Tempfile.new('loadDatabase')
      file.puts("#!/bin/bash -v")
      file.puts(cmd) # Wait till finished
      file.close
      File.chmod(0755, file.path)
      unless settings.batch
        settings.batch = BatchRunner.new(file.path,
                                          "#{whichDb}-Datenbank aus Dump #{dumpFile} wieder herstellen",
                                          "#{whichDb}-Datenbank aus Dump #{dumpFile} erfolgreich wieder hergestellt",
                                          "#{whichDb}-Datenbank konnte nicht wieder hergestellt werden. Fehler in Dumpfile #{dumpFile}?")
      end
      @title = settings.batch.title
      settings.batch.runBatch
    end
  end  # start the server if ruby file executed directly
  
  get '/installElexis' do
    puts "get 1 #{request.path_info}: params #{params}"
    haml :installElexis
  end
  
  post '/run_installElexis' do
    puts "line #{__LINE__}: post #{request.path_info}: params #{params}"
    query = params.map{|key, value| "#{key}=#{value}"}.join("&")
    settings.set(:batch, nil)
    redirect "/run_installElexis?#{query}"
  end
  
  get '/run_installElexis' do
    puts "get #{__LINE__}: #{request.path_info}: params #{params.inspect}"

    # cannot be run using shotgun! Please call it using ruby elexis-cockpit.rub
    unless settings.batch
      installDir = File.join('/opt', params[:subdir])
      cmd = "#{Sinatra::ElexisHelpers.get_hiera('elexis::install_script')} #{params[:url]} #{installDir} #{params[:withDemoDB]}"  
      puts "get #{__LINE__}: #{request.path_info}: cmd ist #{cmd}"
      settings.set(:batch, nil)
      file = Tempfile.new('installElexis')
      file.puts("#!/bin/bash -v")
      file.puts(cmd) # Wait till finished
      file.close
      File.chmod(0755, file.path)
      settings.batch = BatchRunner.new(file.path, 
                                        'Elexis-Version installieren',
                                        "Elexis-Version installiert in #{installDir}",
                                        'Fehler bei der Installation von Elexis')
    end
    @title = settings.batch.title
    settings.batch.runBatch
  end 
    
  switchDbServer = BatchRunner.new("elexis::#{Sinatra::ElexisHelpers.get_hiera("elexis::db_type")}_switch_script", 
                                        'Elexis-Datenbank Server umschalten',
                                        'Elexis-Datenbank Server umgeschalten',
                                        'Fehler beim Umschalten des Elexis-Datenbank Servers')
  switchDbServer.createPages(self, 'switchDbServer')
  
  cmd = "#{Sinatra::ElexisHelpers.get_hiera('elexis::hd_external_format_and_encrypt')} --keyfile #{Sinatra::ElexisHelpers.get_hiera('elexis::hd_external_keyfile')}"      
  backup2external = BatchRunner.new(cmd.clone, 
                                    'Backup auf verschlüsselte externe Festplatte',
                                    'Backup auf verschlüsselte externe Festplatte erfolgreich',
                                    'Fehler beim Backup auf verschlüsselte externe Festplatte')

  backup2external.createPages(self, 'backup2external')
  
  cmd = Sinatra::ElexisHelpers.get_hiera("server::reboot_script", '/sbin/reboot')
  puts "reboot cmd ist #{cmd}"
  reboot = BatchRunner.new(cmd.clone,
                                    'Server neu starten',
                                    'Server sollte jetzt neu starten',
                                    'Fehler beim Neustarten des Servers')
  reboot.createPages(self, 'reboot')

  cmd  = Sinatra::ElexisHelpers.get_hiera("server::halt_script", '/sbin/halt')
  halt = BatchRunner.new(cmd.clone,
                                    'Server anhalten',
                                    'Server sollte jetzt anhalten',
                                    'Fehler beim Anhalten des Servers')
  halt.createPages(self, 'halt')
  

  # start the server if ruby file executed directly
  run! if app_file == $0
end
