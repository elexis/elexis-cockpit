#!/usr/bin/env ruby
require 'watir-webdriver'
require 'fileutils'
require 'pp'
for_manual_tests = %(
  require 'watir-webdriver'
  require 'fileutils'
  require 'pp'
  browser = Watir::Browser.new :firefox
  browser.goto "localhost:9393"
)

ImageDest = File.join(Dir.pwd, 'wiki', 'images')
FileUtils.makedirs(ImageDest, :verbose => true) unless File.exists?(ImageDest)
browsers2test = [:chrome ] # could be any combination of :ie, :firefox, :chrome

@workThread = nil
Port = 9393
Host = 'localhost'

def createScreenshot(browser, added=nil)
  puts "createScreenshot: #{ browser.url.split(Port.to_s).inspect}"
  if browser.url.index('?')
    name = File.join(ImageDest, File.basename(browser.url.split('?')[0]))
  elsif  browser.url.split(Port.to_s)[-1].eql?('/')
    name = File.join(ImageDest, 'home')
  else
    name = File.join(ImageDest, browser.url.split('/')[-1])
  end
  name = "#{name}#{added}.png"
  puts "createScreenshot: #{name}" if $VERBOSE
  browser.screenshot.save (name)
end

def startWebApp(webApp)
  @mainThread = Thread.current
  unless @workThread
    puts "Starting webApp #{webApp} unless #{@workThread.inspect}"
    @workThread = Thread.new do
      @result = system(webApp)
      puts "done webApp #{webApp} died too early"
      @mainThread.kill
    end
  end
  timeToSleep = 0.5
  puts "startWebApp sleep #{timeToSleep}"
  sleep timeToSleep # give it some time to start up
end 

def runOneElexisBatch(browser)
  puts "runOneElexisBatch #{browser.url}"
  browser.window.resize_to(600, 400)
  nrTimes = 1
  while nrTimes < 5
    createScreenshot(browser, "_#{nrTimes}")
    break if /beendet/.match(browser.text)
    nrTimes += 1
    sleep 1
    browser.refresh
  end
end

def runLastButtonWithDefaults(browser)
  if browser.buttons.size == 0
     puts "#{browser.url}: Has no buttons. Skipping"
  else
    # we run the last button
    browser.buttons[-1].click
    runOneElexisBatch(browser)
  end
end

def runLastFormWithDefaults(browser)
  if browser.forms.size == 0
     puts "#{browser.url}: Has no Forms. Skipping"
  else
    # we run the last form
    browser.forms[-1].submit
    runOneElexisBatch(browser)
  end
end

def linkIsInteresting(url)
  if not /#{Host}/i.match(url) or /#{Host}:#{Port}\//i.eql?(url)
    puts "url #{url} is NOT interesting" if $VERBOSE
    return false
  else
    puts "url #{url} is interesting" if $VERBOSE
    return true
  end
end

def testElexisCockpit(whichBrowser, webApp)
  res = false
  homeUrl =  "#{Host}:#{Port}"
  startWebApp(webApp)

  if whichBrowser.eql?(:chrome)
    Selenium::WebDriver::Chrome.path = '/usr/bin/chromium'
    driver = Selenium::WebDriver.for :chrome
    browser = Watir::Browser.new driver
  else
    browser = Watir::Browser.new whichBrowser
  end
  res1 = browser.goto homeUrl
  res2 = browser.wait
  puts "waited for webapp 1 #{res} 2 #{res2}"
  raise "Could not connect to #{webApp} at #{homeUrl} 1 #{res} 2 #{res2}" if not res1 and res2
  browser.window.resize_to(830, 650)
  createScreenshot(browser)
  
  puts "\n\n\nChecking all buttons am in #{browser.url}"
  0.upto(browser.buttons.size-1).each {
    |nr|
      puts "button nr ist #{nr}"
      browser.buttons[nr].click
      runOneElexisBatch(browser)
      browser.goto homeUrl; browser.wait
  }

  browser.goto homeUrl; browser.wait
  puts "\n\n\nChecking last button in all links am in #{browser.url}"
  0.upto(browser.links.size-1).each {
    |nr|
      next unless linkIsInteresting(browser.links[nr].href)
      browser.links[nr].click
      runLastButtonWithDefaults(browser)
      browser.goto homeUrl; browser.wait
  }
  
  # Run last form (if any) in all links
  browser.goto homeUrl; browser.wait
  puts "\n\n\nChecking last form in all links am in #{browser.url}"
  0.upto(browser.links.size-1).each {
    |nr|
      next unless linkIsInteresting(browser.links[nr].href)
      browser.links[nr].click
      runLastFormWithDefaults(browser)
      browser.goto homeUrl; browser.wait
  }
  
  res = true
rescue => e
  puts "rescue in testElexisCockpit"
  puts e.inspect
  puts e.backtrace
ensure
  puts "ensure at end of testElexisCockpit"
  browser.close if browser
  begin
    okay = @workThread.kill
    puts "Killed using thread #{okay}"
    ids = `ps -ef | grep #{webApp}`
    puts ids.inspect
    id = ids.split(' ')[1]
    cmd = "kill -9 #{id}"
    okay = system(cmd)
    puts "Killed #{id} using bash okay #{okay}"
  rescue 
  end
  @workThread.join
  puts "join #{@workThread} done. Returning #{res} "
  return res
end

if $0.eql?( __FILE__)
  startTime = Time.now
  nrBatchFile2Test = 7 # we have 7 batch jobs to test
  browsers2test.each{
    |whichBrowser|
      res = testElexisCockpit(whichBrowser, File.join(Dir.pwd, 'elexis-cockpit.rb'))
      diff = (Time.now-startTime).to_i
      nrScreenshots = Dir.glob(File.join(ImageDest, '*.png')).size
      nrBatchFounds = Dir.glob(File.join(ImageDest, '*_1.png')).size 
      info = "\n   Brauchte #{diff} Sekunden.\n   Erstellte #{nrScreenshots} mit #{nrBatchFounds}/#{nrBatchFile2Test} screenshots."
      if res and Dir.glob(File.join(ImageDest, '*_1.png')).size == nrBatchFile2Test 
        puts "Elexis-Cockpit erfolgreich getestet." + info
        exit 0
      else
        puts "#{whichBrowser}: Fehler beim Testen von Elexis-Cockpit. " + info
        exit 1
      end
  }
end