require 'nokogiri'
require 'net/http'
require 'digest/md5'
require 'open-uri'
require 'openssl'
require 'certified'
require 'httpclient' 
require 'terminal-table'
require 'colorize'
require 'json'

require 'rubygems'
exit if Object.const_defined?(:Ocra)

$VERBOSE = nil


trap "SIGINT" do
	Thread.list.each do |t|
		t.exit unless t == Thread.current
	end
	exit
end


def get_csrf_token(doc)
	csrf_token = doc.css('form > input[type="hidden"]').first
	 csrf_token != nil
		csrf_token = csrf_token.attr('value')
		csrf_token
end

def parse_cookies(all_cookies)
	cookies_array = Array.new
    all_cookies.each { | cookie |
        cookies_array.push(cookie.split('; ')[0])
    }
    cookies = cookies_array.join('; ')
    cookies
end

def create_account(thread_index, password, prefix)

	httpclient = HTTPClient.new
	httpclient.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_NONE
	

	# Pull sign up page
	sign_up_url = "https://club.pokemon.com/us/pokemon-trainer-club/sign-up/"

	registration_form_response = httpclient.get(sign_up_url)

	registration_form_html_parsed = Nokogiri::HTML(registration_form_response.body)

	# Get variables for the initial sign up request
	csrf_token = get_csrf_token(registration_form_html_parsed)

	sign_up_parameters = {
		'csrfmiddlewaretoken' => csrf_token,
		'dob' => "#{1950 + rand(45)}-0#{1 + Random.rand(8)}-#{Random.rand(28)}",
		'country' => "US"
	}.map{|k,v| "#{k}=#{v}"}.join('&')

	headers = {
		'Referer' => sign_up_url
	}

	# Send initial signup request
	sign_up_response = httpclient.post(sign_up_url, sign_up_parameters, headers)
	# We don't really need the info coming from this page, so we'll just build the next parameters

	# Setup final signup request
	final_signup_url = "https://club.pokemon.com/us/pokemon-trainer-club/parents/sign-up"

	final_signup_form_response = httpclient.get(final_signup_url)

	
	if !prefix
		o = [('a'..'z'), ('A'..'Z')].map { |i| i.to_a }.flatten
		username = (0...12).map { o[rand(o.length)] }.join
		email = username
	else
		o = (0..9).to_a
		username = prefix + ((0..6).map { o[rand(o.length)] }.join).to_s
		o = [('a'..'z'), ('A'..'Z')].map { |i| i.to_a }.flatten
		email = (0...12).map { o[rand(o.length)] }.join
	end
	password ||= (0...12).map { o[rand(o.length)] }.join
	email = "#{email.downcase}@divismail.ru"
	md5_email = Digest::MD5.hexdigest(email)

	final_signup_parameters = {
		'csrfmiddlewaretoken' => csrf_token,
		'username' => username,
		'password' => password,
		'confirm_password' => password,
		'email' => email,
		'confirm_email' => email,
		'public_profile_opt_in' => 'False',
		'screen_name' => '',
		'terms' => 'on'
	}.map{|k,v| "#{k}=#{v}"}.join('&')

	headers = {
		'Referer' => final_signup_url
	}

	# Send final sign up request

	response = httpclient.post(final_signup_url, final_signup_parameters, headers)

	response = httpclient.get("https://club.pokemon.com/us/pokemon-trainer-club/parents/email")

	# Time to do email validation

	email_arrived = false
	email_response = ""

	$status[thread_index] = "waiting for email"
	print_table
	tries = 0
	while !email_arrived
		begin
			res = open("http://api.temp-mail.ru/request/mail/id/#{md5_email}").read
			email_response = res
			$status[thread_index] = "email arrived"
			print_table
			email_arrived = true
		rescue
			tries += 1
			raise StandardError if tries == 10
			sleep 5
		end
	end

	xml = Nokogiri::XML(email_response)
	mail_text = xml.xpath("//item")[0].xpath("//mail_text_only")
	mail_text = Nokogiri::HTML(mail_text.text)

	validate_link = mail_text.css("body > table > tbody > tr:nth-child(7) > td > table > tbody > tr > td:nth-child(2) > a").attr('href').value

	validated = false
	while !validated
		validation_response = open(URI(validate_link)).read
		validated = validation_response.include?("Thank you for signing up! Your account is now active.") ? true : false
	end

	# TIME TO LOGIN!

	# Let's get the login form
	login_url = "https://sso.pokemon.com/sso/login?locale=en&service=https://club.pokemon.com/us/pokemon-trainer-club/caslogin"
	response = httpclient.get(login_url)
	doc = Nokogiri::HTML(response.body)

	lt = doc.css("#login-form > input[type=\"hidden\"]:nth-child(1)").attr('value')
	execution = doc.css("#login-form > input[type=\"hidden\"]:nth-child(2)").attr('value')
	_eventId = doc.css("#login-form > input[type=\"hidden\"]:nth-child(3)").attr('value')

	login_parameters = {
		"lt" => lt,
		"execution" => execution,
		"_eventId" => _eventId,
		"username" => username,
		"password" => password,
		"Login" => "Sign In"
	}.map{|k,v| "#{k}=#{v}"}.join('&')
	# Send Login Post

	headers = {
		'Referer' => login_url
	}

	login_response = httpclient.post(login_url, login_parameters, headers)

	
	# Loop through redirects to get all cookies. This sucks but has to be done.
	while(login_response.code == 302)
		login_response = httpclient.get(URI(login_response.headers["Location"]))
	end

	# Time to accept TOS!

	tos_page = 'https://club.pokemon.com/us/pokemon-trainer-club/go-settings'

	tos_page_html = httpclient.get(tos_page).body

	tos_parameters = {
		'csrfmiddlewaretoken' => get_csrf_token(Nokogiri::HTML(tos_page_html)),
		'go_terms' => ' on'
	}.map{|k,v| "#{k}=#{v}"}.join('&')

	headers = {
		'Referer' => tos_page
	}

	response = httpclient.post(tos_page, tos_parameters, headers)


	File.open("export/accounts.txt", 'a') do |file|
		if $conf['output_password']
			file.puts username + $conf['separator'] + password + $conf['end_of_line']
		else
			file.puts username + $conf['end_of_line']
		end
	end
end

$conf = JSON.parse(File.read('config.json')) 

$times = $conf['accounts_per_thread']
$counter = []
$try_count = []
$fails = []
$status = []
$threads = $conf['threads']
$conf['username_prefix'] ||= false


print "\e[H\e[2J"
def print_table
	rows = []
	$threads.times do |i|
		rows << [i.to_s.cyan.bold, $status[i].to_s.cyan.bold, $counter[i].to_s.cyan.bold, $fails[i].to_s.cyan.bold, $try_count[i].to_s.cyan.bold]
	end
	rows << [" ", " ", " ", " ", " "]
	rows << ["N/A".yellow, "TOTALS".yellow, $counter.inject(:+).to_s.green, $fails.inject(:+).to_s.red, $try_count.inject(:+).to_s.yellow]
	table = Terminal::Table.new :title => "GIMME PTC enhanced by xssc", :headings => ["Thread", "Last Email Status", 'Created', 'Fails', 'Trys'], :rows => rows
	print "\r\e[A\e[A\e[A\e[A\e[A" + ("\e[A" * $threads) + "\e[A\e[A\e[A\e[A" + table.to_s
	##### UP for headers			#UP for each rows 		Up for Totals row and empty row
end




threads = []
$threads.times do |i|
	$counter[i] = 0
	$try_count[i] = 0
	$fails[i] = 0
	$status[i] = "Starting"


    threads << Thread.new do
    	
		while($counter[i] < $times)
			begin
				create_account(i, $conf['password'], $conf['username_prefix'])
				$counter[i] += 1
				$try_count[i] += 1
			rescue => e
				$try_count[i] += 1
				$fails[i] += 1
			end
			print_table
		end
	end
	print_table
	sleep(1)
end

threads.each(&:join)
