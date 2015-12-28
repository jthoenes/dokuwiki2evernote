require 'rubygems'
require 'bundler'

Bundler.require(:default, :sinatra)

require './get_evernote_oauth'
run Sinatra::Application
