# Client credentials
OAUTH_CONSUMER_KEY = ENV['OAUTH_CONSUMER_KEY']
OAUTH_CONSUMER_SECRET = ENV['OAUTH_CONSUMER_SECRET']

# Connect to Sandbox server?
SANDBOX = false
enable :sessions

helpers do
  def auth_token
    session[:access_token].token if session[:access_token]
  end

  def client
    @client ||= EvernoteOAuth::Client.new(token: auth_token, consumer_key:OAUTH_CONSUMER_KEY, consumer_secret:OAUTH_CONSUMER_SECRET, sandbox: SANDBOX)
  end

  def user_store
    @user_store ||= client.user_store
  end

  def note_store
    @note_store ||= client.note_store
  end

  def en_user
    user_store.getUser(auth_token)
  end

  def notebooks
    @notebooks ||= note_store.listNotebooks(auth_token)
  end

  def total_note_count
    filter = Evernote::EDAM::NoteStore::NoteFilter.new
    counts = note_store.findNoteCounts(auth_token, filter, false)
    notebooks.inject(0) do |total_count, notebook|
      total_count + (counts.notebookCounts[notebook.guid] || 0)
    end
  end
end

##
# Index page
##
get '/' do
  erb :index
end

##
# Reset the session
##
get '/reset' do
  session.clear
  redirect '/'
end

##
# Obtain temporary credentials
##
get '/requesttoken' do
  callback_url = request.url.chomp("requesttoken").concat("callback")
  begin
    session[:request_token] = client.request_token(:oauth_callback => callback_url)
    redirect '/authorize'
  rescue => e
    @last_error = "Error obtaining temporary credentials: #{e.message}"
    erb :error
  end
end

##
# Redirect the user to Evernote for authoriation
##
get '/authorize' do
  if session[:request_token]
    redirect session[:request_token].authorize_url
  else
    # You shouldn't be invoking this if you don't have a request token
    @last_error = "Request token not set."
    erb :error
  end
end

##
# Receive callback from the Evernote authorization page
##
get '/callback' do
  unless params['oauth_verifier'] || session['request_token']
    @last_error = "Content owner did not authorize the temporary credentials"
    halt erb :error
  end
  session[:oauth_verifier] = params['oauth_verifier']
  begin
    session[:access_token] = session[:request_token].get_access_token(:oauth_verifier => session[:oauth_verifier])
    redirect '/list'
  rescue => e
    @last_error = 'Error extracting access token'
    erb :error
  end
end


##
# Access the user's Evernote account and display account data
##
get '/list' do
  auth_token
end
