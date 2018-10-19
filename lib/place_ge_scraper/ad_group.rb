require_relative '../../environment'

# Group of place.ge real estate ads
class PlaceGeAdGroup
  def initialize(start_date = Date.today, end_date = Date.today, ad_limit = 0)
    set_dates(start_date, end_date)
    @ad_limit = ad_limit
    @errors = []
  end

  def set_dates(start_date, end_date)
    @start_date = start_date
    @end_date = end_date

    check_dates_are_valid
  end

  def check_dates_are_valid
    if @start_date > @end_date
      ScraperLog.logger.error 'The start date cannot be after the end date'
      fail
    elsif @start_date > Date.today
      ScraperLog.logger.error 'The start date cannot be after today'
      fail
    elsif @end_date > Date.today
      ScraperLog.logger.error 'The end date cannot be after today'
      fail
    end
  end

  def dates_to_s
    if @start_date == @end_date
      "on #{@start_date}"
    else
      "between #{@start_date} and #{@end_date}"
    end
  end

  def run
    start_time = Time.now.to_i
    yield self
    end_time = Time.now.to_i
    time_elapsed = Time.at(end_time - start_time).utc.strftime("%H:%M:%S")
    ScraperLog.logger.info "Scraper ran for #{time_elapsed}"
    log_errors
    email_errors
  end

  ########################################################################
  # Scrape ad ids #

  # The site displays VIP ads, then paid ads, then simple ads. So, the scraper
  # finds IDs of ads in the specified time period in the following manner:
  #
  # 1. Checks all VIP ads
  # 2. Checks all paid ads
  # 3. Checks simple ads. When a simple ad is found that does not match
  #    the date criteria, the scraper stops scraping IDs.
  def scrape_and_save_ad_ids
    ScraperLog.logger.info "Finding ids of ads posted #{dates_to_s}"
    ScraperLog.logger.info "Number of ad limited to #{@ad_limit}" unless @ad_limit.nil?

    @finished_scraping_ids = false
    @found_simple_ad_box = false
    @ad_ids = []
    page_num = 1

    if @ad_limit.nil? || @ad_limit > 1000
      limit = 1000
    elsif @ad_limit < 100
      limit = 100
    else
      limit = @ad_limit
    end

    while not_finished_scraping_ids?
      # puts "- ad ids page #{page_num}; ad ids = #{@ad_ids.size}"
      link = "https://place.ge/ge/ads/page:#{page_num}/limit:#{limit}?object_type=all&currency_id=2&mode=list&order_by=date"
      scrape_and_save_ad_ids_from_page(link)
      page_num += 1
    end

    ScraperLog.logger.info "Finished scraping ad ids; found #{@ad_ids.size} total ads"
  end

  def scrape_and_save_ad_ids_from_page(link)
    ScraperLog.logger.info "Retrieving #{link}"
    begin
      retries ||= 0

      page = Nokogiri.HTML(open(link, {ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE}))
    rescue StandardError => error
      error_msg = "Error while scraping ad ids from #{link}: #{error.inspect}"
      ScraperLog.logger.error error_msg
      @errors.push error_msg

      # 502 error is often thrown so let's retry just in case the page will load this time
      retry if (retries += 1) < 3

      return false
    end

    ScraperLog.logger.info "Data successfully retrieved from #{link}"
    ScraperLog.logger.info "Scraping #{link}"

    # get all ads on page
    ad_boxes = page.css('.tr-line')

    if !ad_boxes.nil? && ad_boxes.length > 0
      # process each ad
      ad_boxes.each do |ad_box_html|
        process_ad_box(PlaceGeAdBox.new(ad_box_html))

        # If finished, don't scrape the rest of the ad boxes
        break if finished_scraping_ids?
      end
    end

    ScraperLog.logger.info "Found #{@ad_ids.size} ads posted #{dates_to_s} so far"
  end

  def process_ad_box(ad_box)
    if ad_box.between_dates?(@start_date, @end_date)
      # Save ad id if it has not been saved to @ad_ids yet
      unless @ad_ids.include?(ad_box.id)
        @ad_ids.push(ad_box.id)
        ad_box.save
      end

      # Simple ads are listed in reverse chronological order. Therefore, if
      # the ad group has an end date before today, the scraper should continue
      # until it finds at least one simple ad box that matches the desired time
      # period. Then, the scraper would stop when it finds a simple ad box
      # that does not match the time period (meaning that it is before the
      # start date).
      @found_simple_ad_box = true if not_found_simple_ad_box? && ad_box.simple?
    else
      # Stop scraping if the ad box is not between the dates, is simple, and
      # another simple ad box has been found
      @finished_scraping_ids = true if found_simple_ad_box? && ad_box.simple?
    end

    # If the number of desired ads is limited, and the number of ad ids
    # has reached that limit, stop scraping.
    @finished_scraping_ids = true if !@ad_limit.nil? && @ad_ids.size == @ad_limit
  end

  def finished_scraping_ids?
    @finished_scraping_ids
  end

  def not_finished_scraping_ids?
    !@finished_scraping_ids
  end

  def found_simple_ad_box?
    @found_simple_ad_box
  end

  def not_found_simple_ad_box?
    !@found_simple_ad_box
  end

  ########################################################################
  # Scraping and saving full ad info #

  def scrape_and_save_unscraped_ad_entries
    @ad_ids = Ad.with_unscraped_entry.map(&:place_ge_id)

    ScraperLog.logger.info "Scraping #{@ad_ids.size} ads flagged as unscraped"

    @ad_ids.each_with_index do |ad_id, index|
      scrape_and_save_ad(ad_id)
      remaining_ads_to_scrape = @ad_ids.size - (index + 1)
      if remaining_ads_to_scrape % 20 == 0
        ScraperLog.logger.info "#{remaining_ads_to_scrape} ads remaining to be scraped"
      end
    end
    ScraperLog.logger.info "Finished scraping #{@ad_ids.size} ads flagged as unscraped"

    remind_to_compress_html_copies
  end

  def remind_to_compress_html_copies
    msgs = []
    msgs.push('Reminder - compress copies of ad HTML to save space:')
    msgs.push('')
    msgs.push('rake scraper:compress_html_copies')
    msgs.push('')
    msgs.each do |msg|
      ScraperLog.logger.info msg
      puts msg
    end
  end

  def scrape_and_save_ad(ad_id)
    ScraperLog.logger.info "Scraping info for ad with id #{ad_id}"
    begin
      ad = PlaceGeAd.new(ad_id)
      ad.retrieve_page_and_save_html_copy
      ad.scrape_all
      save_ad(ad)
    rescue StandardError => error
      error_msg = "Ad ID #{ad_id} had following error while being scraped: #{error.inspect}"
      ScraperLog.logger.error error_msg
      @errors.push error_msg

      if error.message == '404 Not Found'
        Ad.find_by_place_ge_id(ad_id).entry_not_found
      end
    end
  end

  def save_ad(ad)
    ScraperLog.logger.info "Saving ad ID #{ad.place_ge_id} to database"
    begin
      ad.save
    rescue StandardError => error
      error_msg = "Ad ID #{ad.place_ge_id} had following error while being saved to database: #{error.inspect}"
      ScraperLog.logger.error error_msg
      @errors.push error_msg
    end
  end

  ########################################################################
  # Error-handling (email, log) #

  def create_error_report
    @error_report = ['Errors thrown by scraper:']

    @errors.each_with_index do |error_msg, index|
      @error_report.push("#{index + 1}: #{error_msg}")
    end
  end

  def email_errors
    return if @errors.empty? # Don't send email if no errors
    create_error_report if @error_report.nil?

    error_body = @error_report.join("\n").gsub('<', '').gsub('>', '')

    error_mail = Mail.new do
      from ENV['FEEDBACK_FROM_EMAIL']
      to ENV['FEEDBACK_TO_EMAIL']
      subject 'Place.Ge Scraper Errors'
      body error_body
    end

    error_mail.deliver!
  end

  def log_errors
    return if @errors.empty? # Don't log anything if no errors
    create_error_report if @error_report.nil?

    @error_report.each { |line| ScraperLog.logger.info line }
  end
end
