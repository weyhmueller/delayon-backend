# delayon.rb

require 'sinatra'
require 'prawn'
require 'pp'
require 'httpi'
require 'json'
require 'digest'
require 'aws-sdk'

configfile = File.read('settings.json')
@@config = JSON.parse(configfile)

Aws::DynamoDB::Client.new(
  access_key_id: @@config['aws']['key'],
  secret_access_key: @@config['aws']['secret'],
  region: @@config['aws']['region']
)
puts @@config['aws']['key'] + " / " + @@config['aws']['secret']

Aws.config.update({
                    region: 'eu-central-1',
                    credentials: Aws::Credentials.new(@@config['aws']['key'], @@config['aws']['secret'])
                  })

Prawn::Font::AFM.hide_m17n_warning = true

def eva2string(eva)
  if eva.to_s.start_with? '8'
    #get station from eva-id
    request = HTTPI::Request.new
    request.url = 'https://api.deutschebahn.com/stada/v2/stations'
    request.headers["Authorization"] = "Bearer " + @@config['token']
    request.headers["Accept"] = "application/json"
    request.query = {:eva => "#{eva}"}

    response = HTTPI.get(request)
    jsondata = JSON.parse(response.body)
    #pp jsondata
    if jsondata['total'] == 1
      stationid = jsondata["result"][0]["name"]
    end
  end
  stationid
end

def string2eva(station)
  if !station.start_with? '8'
    #get eva from station name
    request = HTTPI::Request.new
    request.url = 'https://api.deutschebahn.com/stada/v2/stations'
    request.headers["Authorization"] = "Bearer "+ @@config['token']
    request.headers["Accept"] = "application/json"
    request.query = {:searchstring => station}

    response = HTTPI.get(request)
    jsondata = JSON.parse(response.body)
    #pp jsondata
    if jsondata['total'] == 1
      stationid = jsondata["result"][0]["evaNumbers"][0]["number"]
    end
  else
    stationid = station
  end
  stationid
end

def make_pdf(delay, delayid, stationname, train, delaydate)

  delaydatetext = "am " + Time.parse(delaydate).strftime('%d.%m.%Y')
  delaytext = " keine "
  delaytext =  " #{delay.to_i} Minuten " if delay.to_i > 0
  pdffile = Prawn::Document.new do |pdf|
    now = Time.now
    pdf.image "logo.png", :at => [450, 720], scale: 0.8
    pdf.move_down 10
    pdf.formatted_text [text: 'Verspätungsbescheinigung', size: 20]
    pdf.move_down 30
    pdf.text "Sehr geehrter Kunde,"
    pdf.move_down 20
    pdf.formatted_text [
                         {text: 'Bei Fahrt mit ', styles: []},
                         {text: train.to_s, styles: [:bold]},
                         {text: ' ', styles: []},
                         {text: delaydatetext, styles: [:bold]},
                         {text: ' ist bei der Ankunft in ', styles: []},
                         {text: stationname.to_s, styles: [:bold]},
                         {text: ' eine Verspätung von ', styles: []},
                         {text: "#{delaytext}", :styles => [:bold]},
                         {text: ' aufgetreten.', styles: []}
    ]
    pdf.move_down 20
    pdf.text "Wir bitten um Entschuldigung."
    pdf.move_down 20
    pdf.text "Mit freundlichen Grüßen"
    pdf.move_down 20
    pdf.text "Deutsche Bahn AG"
    pdf.text "Kundendialog"
    pdf.move_down 40
    pdf.text "Auskunfts-ID: #{delayid}, Auskunft erstellt am: #{now.strftime('%d.%m.%Y um %H:%M:%S')}"
    pdf.move_down 10
    pdf.text "Disclaimer:"
    pdf.text "Dieses Dokument wurde im Rahmen des 8. DB Hackathon: Open Data am 15. & 16.12.2017 in Berlin erstellt. Dies ist KEIN offizielles Dokument der Deutschen Bahn AG oder ihrer Tochterunternehmen"
    pdf.move_down 10
    pdf.text "This Document has been created during the 8th DB Hackathon: Open Data on 15. & 16.12.2017 in Berlin. This is NOT an official Document of Deutsche Bahn AG or its subsidiaries."


  end
end

set :bind, @@config['listen']
set :port, @@config['port']

get '/' do
  'Hello world!'
end

get '/delay/:year/:month/:day/:train/:station' do
  evaid = string2eva(params[:station])
  day = params[:day]
  month = params[:month]
  year = params[:year]

  train = params[:train]
  trainno = train.gsub(/[^0-9]/, '')
  puts "http://<base-url>/prod/#{year}/#{month}/#{day}/#{trainno}/#{evaid}"
  data = get_from_api(year,month,day,trainno,evaid)

  trainno = data['trainCategory'] + " " + data['trainNumber']
  pa = if !data['planned'].nil?
         data['planned']['arrival']
         data['changed']['arrival']
       end
  parrival = Time.new(pa[0],pa[1],pa[2],pa[3],pa[4])
  ca = data['changed']['arrival']
  carrival = Time.new(ca[0],ca[1],ca[2],ca[3],ca[4])
  delay = ((carrival - parrival) / 60).ceil

  now = Time.now.iso8601
  delayid = Digest::SHA256.hexdigest("#{now}#{evaid}#{trainno}#{rand(100)}")
  delayid.upcase!
  delayid = delayid[0...6]

  dynamodb = Aws::DynamoDB::Client.new(region: 'eu-central-1')
  item = {
    delayid: delayid,
    delay: delay,
    delaydate: carrival.to_s,
    station: evaid,
    train: trainno
  }
  dbparams = {
    table_name: 'DBHackathon8Delay',
    item: item
  }

  begin
    result = dynamodb.put_item(dbparams)

  rescue  Aws::DynamoDB::Errors::ServiceError => error
    puts 'Unable to add:'
    puts error.message
  end
  if params[:pdf]
    redirect( '/pdf/' + delayid)
  else
    content_type :json
    { delayid: delayid }.to_json
  end
end

get '/delay/:train/:station' do
  day = Time.now.day
  month = Time.now.month
  year = Time.now.year

 redirect "/delay/#{year}/#{month}/#{day}/#{params[:train]}/#{params[:station]}"

end

def get_from_api(year,month,day,train,evaid)
    jsondata = '{}'
    request = HTTPI::Request.new
    request.url = "https://4m0gbu7t6j.execute-api.eu-central-1.amazonaws.com/prod/#{year}/#{month}/#{day}/#{train}/#{evaid}"
    request.headers["Accept"] = "application/json"
    response = HTTPI.get(request)
    jsondata = JSON.parse(response.body) if response.body.length > 2
  jsondata
end



get '/db/:year/:month/:day/:type/:train/:station/:delay' do
  evaid = string2eva(params[:station])
  day = params[:day]
  month = params[:month]
  year = params[:year]
  delay = params[:delay]

  train = params[:type] + " " + params[:train]
  trainno = train.gsub(/[^0-9]/, '')
  now = Time.now.iso8601
  delayid = Digest::SHA256.hexdigest(now + evaid + trainno + rand(100).to_s)
  delayid.upcase!
  delayid = delayid[0...6]

  dynamodb = Aws::DynamoDB::Client.new(region: 'eu-central-1')
  item = {
    delayid: delayid,
    delay: delay,
    delaydate: Date.parse("#{year}-#{month}-#{day}").to_s,
    station: evaid,
    train: train
  }
  dbparams = {
    table_name: 'DBHackathon8Delay',
    item: item
  }

  begin
    result = dynamodb.put_item(dbparams)

  rescue  Aws::DynamoDB::Errors::ServiceError => error
    puts 'Unable to add:'
    puts error.message
  end
  if params[:pdf]
    redirect( '/pdf/' + delayid)
  else
    content_type :json
    { delayid: delayid }.to_json
  end
end

get '/pdf/:id' do
  #  get data from DB and re-create pdf
  now = Time.now.iso8601
  dynamodb = Aws::DynamoDB::Client.new(region: 'eu-central-1')


  params1 = {
    table_name: 'DBHackathon8Delay',
    key: {
      delayid: params[:id],
    }
  }

  begin
    result = dynamodb.get_item(params1)

    if result.item == nil
      puts 'Could not find delay'
      halt 404
      #exit 0
    else

    #pp result.item['train']


    stationname = eva2string(result.item['station'].to_i.to_s)

    pdffile = make_pdf(result.item['delay'], result.item['delayid'], stationname, result.item['train'], result.item['delaydate'])

    x = pdffile.render
    attachment('test.pdf','application/pdf')
    x

    end
  end
end