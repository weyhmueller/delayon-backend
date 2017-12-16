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
Prawn::Font::AFM.hide_m17n_warning = true

def eva2string(eva)
  if eva.start_with? '8'
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
    request.headers["Authorization"] = "Bearer 99a09b10397ccac09251f15a90301185"
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
       else
         data['changed']['arrival']
       end
  parrival = Time.new(pa[0],pa[1],pa[2],pa[3],pa[4])
  ca = data['changed']['arrival']
  carrival = Time.new(ca[0],ca[1],ca[2],ca[3],ca[4])
  delay = ((carrival - parrival) / 60).ceil

  now = Time.now.iso8601
  delayid = Digest::SHA256.hexdigest(now + evaid + trainno + rand(100).to_s)
  delayid.upcase!
  delayid = delayid[0...6]

  dynamodb = Aws::DynamoDB::Client.new(region: 'eu-central-1')
  item = {
    delayid: delayid,
    delay: delay,
    station: evaid,
    train: trainno
  }
  params = {
    table_name: 'DBHackathon8Delay',
    item: item
  }

  begin
    result = dynamodb.put_item(params)

  rescue  Aws::DynamoDB::Errors::ServiceError => error
    puts 'Unable to add:'
    puts error.message
  end
  redirect( '/pdf/' + delayid)
end

get '/delay/:train/:station' do
  evaid = string2eva(params[:station])
  day = Time.now.day
  month = Time.now.month
  year = Time.now.year

  train = params[:train]
  trainno = train.gsub(/[^0-9]/, '')
  #puts "http://<base-url>/prod/#{year}/#{month}/#{day}/#{trainno}/#{evaid}"
  data = get_from_api(year,month,day,trainno,evaid)
 #pp data

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

def make_pdf(delay, delayid, stationname, train)

  delaytext = " keine "
  delaytext =  " #{delay.to_i} Minuten " if delay.to_i > 0
  pdffile = Prawn::Document.new do |pdf|
    now = Time.now
    pdf.image "logo.png", :at => [450, 720], scale: 0.8
    pdf.formatted_text [text: 'Verspätungsbescheinigung', size: 20]
    pdf.move_down 20
    pdf.formatted_text [
                         {text: train.to_s, styles: [:bold]},
                         {text: ' hatte im Bahnhof ', styles: []},
                         {text: stationname.to_s, styles: [:bold]},
                         {text: "#{delaytext}", :styles => [:bold]},
                         {text: "Verspätung.", styles: []}
                       ]
    pdf.move_down 40
    pdf.text "ID: #{delayid}, Auskunft erstellt am: #{now.strftime('%d.%m.%Y um %H:%M:%S')}"

  end
end

get '/pdf/:train/:station/:delay' do
  # create pdf and save data to DB

  stationname = eva2string(params[:station])
  stationid = params[:station]
  train = params[:train]
  delay = params[:delay]

  #save information to db
  now = Time.now.iso8601
  delayid = Digest::SHA256.hexdigest(now + params[:station] + params[:train] + rand(100).to_s)
  delayid.upcase!
  delayid = delayid[0...6]

  dynamodb = Aws::DynamoDB::Client.new(region: 'eu-central-1')
  item = {
    delayid: delayid,
    delay: params[:delay].to_i,
    station: stationid,
    train: params[:train]
  }
  params = {
    table_name: 'DBHackathon8Delay',
    item: item
  }

  begin
    result = dynamodb.put_item(params)

  rescue  Aws::DynamoDB::Errors::ServiceError => error
    puts 'Unable to add:'
    puts error.message
  end

  pdffile = make_pdf(delay, delayid, stationname, train)
  x = pdffile.render
  attachment('test.pdf','application/pdf')
  x
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


    stationname = eva2string(result.item['station'])

    pdffile = make_pdf(result.item['delay'], result.item['delayid'], stationname, result.item['train'])

    x = pdffile.render
    attachment('test.pdf','application/pdf')
    x

    end
  end
end