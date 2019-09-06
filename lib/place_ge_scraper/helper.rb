require_relative '../../environment'

# Adds place.ge specific helper methods to String
class String
  def remove_non_numbers
    gsub(/[^0-9]/, '')
  end

  def remove_numbers
    gsub(/[0-9]/, '')
  end

  def to_nil_or_i
    empty? ? nil : to_i
  end

  def to_nil_if_empty
    if empty?
      return nil
    else
      return self
    end
  end
end

# Adds place.ge specific helper methods to Nokogiri
class Nokogiri::XML::Node
  def detail_value(detail_label)
    xpath("//*[contains(concat(' ', @class, ' '), ' detailBox2 ' )][descendant::div[@class='detailLeft'][contains(., '#{detail_label}')]]//*[contains(concat(' ', @class, ' '), ' detailRight ')]/text()").text
  end
end

# update github with any changes
def update_data_github
  unless !ENV['PROJECT_ENV'].nil? && !ENV['PROJECT_ENV'].empty? && ENV['PROJECT_ENV'].downcase == 'production'
    ScraperLog.logger.info 'NOT updating github because environment is not production'
    return false
  end

  ScraperLog.logger.info 'pushing data files to github'

  `cd data && git add -A`
  `cd data && git commit -m 'Added new the csv file for the last month'`
  `cd data && git push origin master`

  body = [
    "The Place.ge Scraper has finished scraping the previous month!",
    "You can download the new data file at: #{ENV['GITHUB_DATA_URL']}"
  ]

  send_email(to: ENV['FEEDBACK_SUCCESS_EMAIL'], subject: 'New Data is Ready', body: body.join("\n"))

end


# most popular user agents as of 2019-04-18
# taken from: https://techblog.willshouse.com/2012/01/03/most-common-user-agents/
USER_AGENTS = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3683.86 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/72.0.3626.121 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:66.0) Gecko/20100101 Firefox/66.0',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3683.103 Safari/537.36',
  'Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3683.86 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.0.3 Safari/605.1.15',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3683.86 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:65.0) Gecko/20100101 Firefox/65.0',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3683.86 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/72.0.3626.121 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1 Safari/605.1.15',
  'Mozilla/5.0 (Windows NT 6.1; rv:60.0) Gecko/20100101 Firefox/60.0',
  'Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:66.0) Gecko/20100101 Firefox/66.0',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/64.0.3282.140 Safari/537.36 Edge/18.17763',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/64.0.3282.140 Safari/537.36 Edge/17.17134',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3683.75 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3683.86 Safari/537.36',
  'Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/72.0.3626.121 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.14; rv:66.0) Gecko/20100101 Firefox/66.0',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3683.103 Safari/537.36',
]

def get_user_agent
  USER_AGENTS.sample
end

def send_email(args={})
  settings = defaults={
    to: ENV['FEEDBACK_TO_EMAIL'],
    subject: '',
    body: nil
  }.merge(args)

  email = Mail.new do
    from ENV['FEEDBACK_FROM_EMAIL']
    to settings[:to]
    subject "#{ENV['EMAIL_SUBJECT_PREFIX']} - #{settings[:subject]}"
    body settings[:body]
  end

  email.deliver!
end