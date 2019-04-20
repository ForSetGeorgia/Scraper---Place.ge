require_relative '../../environment'
require_relative 'helper'

# Group of place.ge real estate ads
class PlaceGeAdGroup
  def initialize(start_date = Date.today, end_date = Date.today, ad_limit = 0)
    set_dates(start_date, end_date)
    @ad_limit = ad_limit
    @errors = []
    @retry_attempts = 4
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
  def scrape_and_save_ad_ids(fast_search = false)
    ScraperLog.logger.info "Finding ids of ads posted #{dates_to_s}"
    ScraperLog.logger.info "Number of ad limited to #{@ad_limit}" unless @ad_limit.nil?
    ScraperLog.logger.info "Fast_search = #{fast_search}"

    @finished_scraping_ids = false
    @found_simple_ad_box = false
    @ad_ids = []
    # 2019-01 - place.ge changed the url so that page:1 no longer exists
    # so we have to start with page 2
    link = "https://place.ge/ge/ads/page:[page_num]?limit=[limit]&object_type=all&currency_id=2&mode=list&order_by=date"
    page_num = 2 #1
    max_page_limit = 750
    min_page_limit = 100

    if @ad_limit.nil? || @ad_limit > max_page_limit
      limit = max_page_limit
    elsif @ad_limit < min_page_limit
      limit = min_page_limit
    else
      limit = @ad_limit
    end

    if fast_search
      ScraperLog.logger.info "RUNNING FAST SEARCH"

      total_pages = get_total_pages(link, page_num, limit)
      ScraperLog.logger.info "TOTAL PAGES = #{total_pages}"
      starting_page = determine_starting_page(link, limit, (total_pages / 2), total_pages, page_num)

      page_num = starting_page if starting_page
    end
    ScraperLog.logger.info "@@@@@@@@@@@@@@@@@@"
    ScraperLog.logger.info "starting page = #{page_num}"

    # go sequentially through pages
    while not_finished_scraping_ids?
      # puts "- ad ids page #{page_num}; ad ids = #{@ad_ids.size}"
      scrape_and_save_ad_ids_from_page(create_link(link, page_num, limit))
      page_num += 1
    end

    ScraperLog.logger.info "Finished scraping ad ids; found #{@ad_ids.size} total ads"
  end

  # create the link with the page num and limit inserted into it
  def create_link(link, page_num, limit)
    link.gsub('[page_num]', page_num.to_s).gsub('[limit]', limit.to_s)
  end

  # look at the pagination to determine how many pages total there are
  def get_total_pages(link, page_num, limit)
    total = 0
    formatted_link = create_link(link, page_num, limit)

    begin
      retries ||= 0

      page = Nokogiri.HTML(open(formatted_link, {
        proxy: 'http://' + Proxy.get_proxy,
        "User-Agent" => get_user_agent,
        ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE
      }))

      spans = page.css('.pageBg .boxPages span')
      total = spans[-3].css('a').text.to_i
    rescue StandardError => error
      error_msg = "Error while scraping ad ids from #{formatted_link}: #{error.inspect}"
      ScraperLog.logger.error error_msg

      # 502 error is often thrown so let's retry just in case the page will load this time
      retry if (retries += 1) < @retry_attempts

      return false
    end

    return total
  end

  # jump around to find the page that has content we want
  # (
  #   non fast search starts at page_num and goes sequentially until the dates have been found and processed
  #   this can take a long time for we are running last month scraper, the pages with this text is well after page 100
  # )
  # - get first page and look at pagination to see how many pages total
  # - go to middle page and check dates
  # - based on dates either jump ahead 50% or skip back 50%
  # - continue until find the starting page
  def determine_starting_page(link, limit, current_page, total_pages, last_page)
    start_page = nil
    ScraperLog.logger.info "====================== searching a new page ======================"
    ScraperLog.logger.info "current = #{current_page}"
    ScraperLog.logger.info "last = #{last_page}"
    ScraperLog.logger.info "total_pages = #{total_pages}"
    ScraperLog.logger.info "limit = #{limit}"
    ScraperLog.logger.info "start date = #{@start_date}"
    ScraperLog.logger.info "end date = #{@end_date}"
    ScraperLog.logger.info "-------- getting page data ---------"

    formatted_link = create_link(link, current_page, limit)

    begin
      retries ||= 0

      # get the page
      page = Nokogiri.HTML(open(formatted_link, {
        proxy: 'http://' + Proxy.get_proxy,
        "User-Agent" => get_user_agent,
        ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE
      }))

      # get all simple ads
      simple_ads = page.css('.tr-line.simple-ad')
      if !simple_ads.nil? && simple_ads.length > 0
        # look at the first and last ad to determine if we found the starting page
        ad_box_first = PlaceGeAdBox.new(simple_ads.first)
        ad_box_last = PlaceGeAdBox.new(simple_ads.last)
        ScraperLog.logger.info "first date = #{ad_box_first.pub_date}"
        ScraperLog.logger.info "last date = #{ad_box_last.pub_date}"

        # - if first ad date > @end_date && last ad date in between start and end, then found starting page
        # - else if first ad date and last ad date > @end_date, not far enough, need to increase page number
        # - else if first ad date and last ad date < @start_date, too far, need to decrease page number
        # - else if first and last ad date between start and end, we found the dates, need to decrease page number to find start
        if ad_box_first.pub_date > @end_date && ad_box_last.between_dates?(@start_date, @end_date)
          ScraperLog.logger.info "-> found starting page!"
          # found the starting page!
          start_page = current_page
        elsif (current_page - last_page).abs == 1
          ScraperLog.logger.info "-> only one page difference between current and last page, so just using the smaller for the start page"
          # there is only one page difference, so just take the smaller page as the start page
          start_page = last_page > current_page ? current_page - 1 : last_page
        elsif ad_box_first.pub_date > @end_date && ad_box_last.pub_date > @end_date
          ScraperLog.logger.info "-> have not gone far enough yet"
          # not far enough, jump ahead
          start_page = determine_starting_page(link, limit, (current_page + (current_page - last_page).abs / 2), total_pages, current_page)
        elsif (ad_box_first.pub_date < @start_date && ad_box_last.pub_date < @start_date) ||
          (ad_box_first.between_dates?(@start_date, @end_date) && ad_box_last.between_dates?(@start_date, @end_date))
          ScraperLog.logger.info "-> have gone too far"
          # too far, jump back
          start_page = determine_starting_page(link, limit, (current_page - (current_page - last_page).abs / 2), total_pages, current_page)
        end

      end
    rescue StandardError => error
      error_msg = "Error while scraping ad ids from #{formatted_link}: #{error.inspect}"
      ScraperLog.logger.error error_msg

      # 502 error is often thrown so let's retry just in case the page will load this time
      retry if (retries += 1) < @retry_attempts

      return false
    end

    return start_page
  end

  def scrape_and_save_ad_ids_from_page(link)
    ScraperLog.logger.info "Retrieving #{link}"
    begin
      retries ||= 0

      page = Nokogiri.HTML(open(link, {
        proxy: 'http://' + Proxy.get_proxy,
        "User-Agent" => get_user_agent,
        ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE
      }))
    rescue StandardError => error
      error_msg = "Error while scraping ad ids from #{link}: #{error.inspect}"
      ScraperLog.logger.error error_msg
      @errors.push error_msg

      # 502 error is often thrown so let's retry just in case the page will load this time
      retry if (retries += 1) < @retry_attempts

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

  def scrape_and_save_unscraped_ad_entries_with_hydra
    @start = Time.now
    @ad_ids = Ad.with_unscraped_entry.map(&:place_ge_id)

    # scrape the ads
    run_hydra

    # if there were scraping errors, re-process the ads that had errors
    if @ad_ids_scrape_errors.length > 0
      ScraperLog.logger.info "There were scraping errors, trying to re-process the ads"
      @start = Time.now
      @ad_ids = @ad_ids_scrape_errors
      run_hydra
    end

    # do it one more time just in case there were still errors
    if @ad_ids_scrape_errors.length > 0
      ScraperLog.logger.info "There were still scraping errors, trying one last time to re-process the ads"
      @start = Time.now
      @ad_ids = @ad_ids_scrape_errors
      run_hydra
    end

    remind_to_compress_html_copies
  end

  def run_hydra
    ScraperLog.logger.info "Scraping #{@ad_ids.size} ads flagged as unscraped with hydra"

    @ad_ids_scrape_errors = []

    #initiate hydra
    hydra = Typhoeus::Hydra.new(max_concurrency: 5)
    Typhoeus::Config.user_agent = get_user_agent

    @total_to_process = @ad_ids.length
    @total_left_to_process = @ad_ids.length

    @ad_ids.each_with_index do |ad_id, index|
      hydra.queue(build_hydra_request(ad_id))
    end

    hydra.run

    ScraperLog.logger.info "------------------------------"
    ScraperLog.logger.info "It took #{((Time.now - @start) / 60).round(2)} minutes to process #{@ad_ids.size} items"
    ScraperLog.logger.info "------------------------------"

    # see if there are any ad ids that had errors while scraping
    ScraperLog.logger.info "------------------------------"
    ScraperLog.logger.info "There are #{@ad_ids_scrape_errors.length} ads that need to be rescraped due to errors"
    ScraperLog.logger.info "------------------------------"

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

  def build_hydra_request(ad_id)
    request = Typhoeus::Request.new("#{PlaceGeAd.link_for_id(ad_id)}",
                followlocation: true,
                ssl_verifypeer: false,
                ssl_verifyhost: 0,
                proxy: Proxy.get_proxy)

    request.on_complete do |response|
      if response.success?
        ScraperLog.logger.info "Scraped info for ad with id #{ad_id}"
        ad = PlaceGeAd.new(ad_id, response.body)
        ad.save_html_copy
        ad.scrape_all
        save_ad(ad)
      elsif response.timed_out?
        # aw hell no
        ScraperLog.logger.error "Error while scraping ad from #{response.request.url}: response timeout"
        @ad_ids_scrape_errors << ad_id
      elsif response.code == 0
        # Could not get an http response, something's wrong.
        ScraperLog.logger.error "Error while scraping ad from #{response.request.url}: html response code = 0"
        @ad_ids_scrape_errors << ad_id
      elsif response.code == 404
        # page could not be found
        ScraperLog.logger.error "Error while scraping ad from #{response.request.url}: html response code = 404"
      else
        # Received a non-successful http response.
        ScraperLog.logger.error "Error while scraping ad from #{response.request.url}: html response code = #{response.code}"
        @ad_ids_scrape_errors << ad_id
      end

      # decrease counter of items to process
      @total_left_to_process -= 1
      if @total_left_to_process % 25 == 0
        ScraperLog.logger.info "*** There are #{@total_left_to_process} ads left to process; time so far = #{(Time.now - @start).round(2)} seconds"
      end

    end

    return request
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
