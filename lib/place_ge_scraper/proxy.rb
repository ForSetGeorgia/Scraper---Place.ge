require_relative '../../environment'
require_relative 'helper'

module Proxy
  # list of proxies are taken from: https://www.proxy-list.download/api/v1
  API_URL = 'https://www.proxy-list.download/api/v1/get?type=http&anon=elite&country='
  COUNTRIES = ['GE', 'AM', 'TR']
  FILE_PATH = 'proxies.csv'

  def self.update_proxy_list
    ScraperLog.logger.info "Updating proxy list"
    proxies = []
    COUNTRIES.each do |country|
      request = open(API_URL + country, {"User-Agent" => get_user_agent, ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE})
      proxies << request.read.split("\r\n")
    end
    proxies.flatten!

    # write to file
    CSV.open(FILE_PATH, 'wb') do |csv|
      proxies.each do |proxy|
        csv << [proxy]
      end
    end
    ScraperLog.logger.info "Proxy list updated"
  end

  def self.get_proxy
    if !File.exist?(FILE_PATH)
      update_proxy_list
    end
    proxies = CSV.read(FILE_PATH)
    proxies.sample.first
  end
end