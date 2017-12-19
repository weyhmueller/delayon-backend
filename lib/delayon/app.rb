
# app.rb
module DelayOn
  PUNCTUALLY = 0
  DELAYED = 1
  CANCELLED = 2
  PROGNOSED = 3
  UNKNOWN = 4

  INFINITY = +1.0 / 0.0

  # The main app class
  class App < Sinatra::Base
    include DelayOn::JSONHelper
    include DelayOn::DBApiHelper

    class << self
      attr_accessor :config
    end

    configfile = File.read('settings.json')
    @config = JSON.parse(configfile)

    #Aws::DynamoDB::Client.new(
    #  access_key_id: @@config['aws']['key'],
    #  secret_access_key: @@config['aws']['secret'],
    #  region: @@config['aws']['region']
    #)

    set :bind, config['listen']
    set :port, config['port']

    Aws.config.update(
      region: App.config['aws']['region'],
      credentials: Aws::Credentials.new(App.config['aws']['key'], App.config['aws']['secret'])
    )

    Prawn::Font::AFM.hide_m17n_warning = true



    def eva2string(eva)
      if eva.to_s.start_with? '8'
        # get station from eva-id
        request = prepare_db_api_request(App.config['token'], 'https://api.deutschebahn.com/stada/v2/stations', eva: eva.to_s)
        response = HTTPI.get(request)
        stationid = get_unique_json_element(response.body, 'name')
        stationid ||= eva.to_s
      else
        stationid = eva.to_s
      end
      stationid
    end

    def string2eva(station)
      if !station.start_with? '8'
        # get eva from station name
        request = prepare_db_api_request(self.config['token'], 'https://api.deutschebahn.com/stada/v2/stations', searchstring: station)
        response = HTTPI.get(request)
        stationid = get_unique_json_element(response.body, 'evaNumbers')[0]['number']
        stationid ||= station
      else
        stationid = station
      end
      stationid
    end

    def make_pdf(delay, delayid, stationname, train, delaydate, delaystate, timestamp)
      sorry = false
      ddate = Time.parse(delaydate)
      delaydatetext = ddate.strftime('%d.%m.%Y')
      delaydatetime = ddate.strftime('%H:%M')
      delaytext = "#{delay.to_i} Minuten"
      pdffile = Prawn::Document.new do |pdf|
        now = Time.at(timestamp)
        pdf.image 'logo.png', at: [450, 720], scale: 0.8
        pdf.move_down 10
        pdf.formatted_text [text: 'Bescheinigung über Zugverspätung', size: 20] if delaystate != PROGNOSED
        pdf.formatted_text [text: 'Verspätungsprognose', size: 20] if delaystate == PROGNOSED
        pdf.formatted_text [text: 'Bescheinigung über Zugausfall', size: 20] if delaystate == CANCELLED

        pdf.move_down 30
        pdf.text 'Sehr geehrter Kunde,'
        pdf.move_down 20
        case delaystate
        when DELAYED
          pdf.text "bei Ihrer Fahrt mit <b>#{train}</b> am <b>#{delaydatetext}</b> nach <b>#{stationname}</b>," \
                   " planmäßige Ankunft dort um <b>#{delaydatetime} Uhr</b>, ist <b>eine Verspätung von #{delaytext}</b> aufgetreten.",
                   inline_format: true
          sorry = true
        when PROGNOSED
          pdf.text "bei Ihrer Fahrt mit <b>#{train}</b> am <b>#{delaydatetext}</b> nach <b>#{stationname}</b>," \
                   " planmäßige Ankunft dort um <b>#{delaydatetime} Uhr</b>, erwarten wir <b>eine Verspätung von #{delaytext}</b>. " \
                   'Diese Auskunft ist unverbindlich',
                   inline_format: true
        when CANCELLED
          pdf.text "leider ist die Fahrt mit <b>#{train}</b> am <b>#{delaydatetext}</b> nach <b>#{stationname}</b>," \
                   " planmäßige Ankunft dort um <b>#{delaydatetime} Uhr</b>, <b>ausfgefallen</b>. " \
                   'Diese Auskunft ist unverbindlich',
                   inline_format: true
        when PUNCTUALLY
          pdf.text "bei Ihrer Fahrt mit <b>#{train}</b> am <b>#{delaydatetext}</b> nach <b>#{stationname}</b>," \
                   " planmäßige Ankunft dort um <b>#{delaydatetime} Uhr</b>, ist <b>keine Verspätung</b> aufgetreten.",
                   inline_format: true
        when UNKNOWN
          pdf.text "zu Ihrer Fahrt mit <b>#{train}</b> am <b>#{delaydatetext}</b> nach <b>#{stationname}</b>," \
                   " planmäßige Ankunft dort um <b>#{delaydatetime} Uhr</b>, liegen uns leider keine Verspätungsdaten" \
                   ' vor. Bitte wenden Sie sich an Ihr Reisezentrum vor Ort.',
                   inline_format: true
        else
          pdf.text 'Leider ist die Erstellung einer Verspätungsbescheinigung derzeit aus technischen Gründen nicht möglich.',
                   inline_format: true
          sorry = true
        end
        if sorry
          pdf.move_down 20
          pdf.text 'Wir bitten um Entschuldigung.'
        end
        pdf.move_down 20
        pdf.text 'Mit freundlichen Grüßen'
        pdf.move_down 20
        pdf.text 'Deutsche Bahn AG'
        pdf.text 'Kundendialog'
        pdf.move_down 40
        pdf.text "Auskunfts-ID: <b>#{delayid}</b>, Auskunft erstellt am: #{now.strftime('%d.%m.%Y um %H:%M:%S')} Uhr.",
                 inline_format: true
        pdf.move_down 10
        pdf.text 'Disclaimer:'
        pdf.text 'Dieses Dokument wurde im Rahmen des 8. DB Hackathon: Open Data am 15. & 16.12.2017 in Berlin erstellt.' \
                 ' Dies ist KEIN offizielles Dokument der Deutschen Bahn AG oder ihrer Tochterunternehmen'
        pdf.move_down 10
        pdf.text 'This Document has been created during the 8th DB Hackathon: Open Data on 15. & 16.12.2017 in Berlin.' \
                 ' This is NOT an official Document of Deutsche Bahn AG or its subsidiaries.'
      end
      attachment("test.pdf", "application/pdf")
      #attachment
      pdffile.render
    end



    # get '/' do
    #  File.read('index.html')
    # end

    get '/delay/:year/:month/:day/:train/:station' do
      evaid = string2eva(params[:station])
      day = params[:day]
      month = params[:month]
      year = params[:year]

      train = params[:train]
      trainno = train.gsub(/[^0-9]/, '')
      puts "http://<base-url>/prod/#{year}/#{month}/#{day}/#{trainno}/#{evaid}"
      data = get_from_api(year, month, day, trainno, evaid)
      if data['date'].nil?
        # no data in json (unknown)
        delaystate = UNKNOWN
        delay = 0
        parrival = Time.new(year, month, day)
      else
        train = data['trainCategory'] + ' ' + data['trainNumber']
        pa = data['planned']['arrival']
        parrival = Time.new(pa[0], pa[1], pa[2], pa[3], pa[4])
        ca = if !data['changed'].nil?
               data['changed']['arrival']
             else
               data['planned']['arrival']
             end
        # ca = data['changed']['arrival']
        carrival = Time.new(ca[0], ca[1], ca[2], ca[3], ca[4])
        puts parrival
        puts carrival
        delay = ((carrival - parrival) / 60).ceil
        delaystate = case delay
                     when 'C'
                       CANCELLED
                     when 0..INFINITY
                       if Time.now < carrival
                         PROGNOSED
                       else
                         DELAYED
                       end
                     else
                       PUNCTUALLY
                     end
        puts delaystate / delay

      end
      now = Time.now.iso8601
      # noinspection RubyResolve
      delayid = Digest::SHA256.hexdigest("#{now}#{evaid}#{train}#{rand(100)}")
      delayid.upcase!
      delayid = delayid[0...6]

      dynamodb = Aws::DynamoDB::Client.new
      item = {
        delayid: delayid,
        delay: delay,
        delaydate: parrival.to_s,
        station: evaid,
        train: train,
        state: delaystate.to_i,
        timestamp: Time.now.to_i
      }
      dbparams = {
        table_name: 'DBHackathon8Delay',
        item: item
      }

      begin
        result = dynamodb.put_item(dbparams)
      rescue Aws::DynamoDB::Errors::ServiceError => error
        puts 'Unable to add:'
        puts error.message
      end
      if params[:pdf]
        redirect('/pdf/' + delayid)
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

    def get_from_api(year, month, day, train, evaid)
      jsondata = '{}'
      request = HTTPI::Request.new
      request.url = "https://4m0gbu7t6j.execute-api.eu-central-1.amazonaws.com/prod/#{year}/#{month}/#{day}/#{train}/#{evaid}"
      request.headers['Accept'] = 'application/json'
      response = HTTPI.get(request)
      jsondata = JSON.parse(response.body) if response.body.length > 2
      jsondata
    end

    get '/db/:year/:month/:day/:hour/:minute/:type/:train/:station/:delay' do
      evaid = string2eva(params[:station])
      day = params[:day]
      month = params[:month]
      year = params[:year]
      hour = params[:hour]
      minute = params[:minute]

      delay = params[:delay]

      delaystate = case delay
                   when delay == 'C'
                     CANCELLED
                     delay = -1
                   when delay.to_i > 0
                     DELAYED
                   else
                     PUNCTUALLY
                     delay = 0
                   end

      train = params[:type] + ' ' + params[:train]
      trainno = train.gsub(/[^0-9]/, '')
      now = Time.now.iso8601
      # noinspection RubyResolve
      delayid = Digest::SHA256.hexdigest(now + evaid + trainno + rand(100).to_s)
      delayid.upcase!
      delayid = delayid[0...6]

      dynamodb = Aws::DynamoDB::Client.new
      item = {
        delayid: delayid,
        delay: delay,
        delaydate: Date.parse("#{year}-#{month}-#{day} #{hour}:#{minute}:00").to_s,
        station: evaid,
        train: train,
        state: delaystate,
        timestamp: Time.now.to_i
      }
      dbparams = {
        table_name: 'DBHackathon8Delay',
        item: item
      }

      begin
        result = dynamodb.put_item(dbparams)
      rescue Aws::DynamoDB::Errors::ServiceError => error
        puts 'Unable to add:'
        puts error.message
      end
      if params[:pdf]
        redirect('/pdf/' + delayid)
      else
        content_type :json
        { delayid: delayid }.to_json
      end
    end

    get '/pdf/:id' do
      #  get data from DB and create pdf
      dynamodb = Aws::DynamoDB::Client.new
      params1 = {
        table_name: 'DBHackathon8Delay',
        key: {
          delayid: params[:id]
        }
      }
      begin
        result = dynamodb.get_item(params1)
        if result.item.nil?
          puts 'Could not find delay'
          halt 404
        else
          delaystate = if result.item['state'].nil?
                         DELAYED
                       else
                         result.item['state']
                       end
          stationname = eva2string(result.item['station'].to_i.to_s)
          timestamp = if result.item['timestamp'].nil?
                        Time.now.to_i
                      else
                        result.item['timestamp'].to_i
                      end
          pp result.item
          make_pdf(
            result.item['delay'],
            result.item['delayid'],
            stationname,
            result.item['train'],
            result.item['delaydate'],
            delaystate,
            timestamp
          )
        end
      end
    end
  end
end