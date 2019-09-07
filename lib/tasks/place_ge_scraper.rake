require_relative '../../environment'
require_relative 'helpers'



namespace :scraper do

  namespace :main_scrape_tasks do
    ########################################################################
    # Tasks for calling main scrape tasks together #

    desc 'Perform monthly scrape tasks'
    task :previous_month, [:optional_number_months_ago] do |_t, args|
      ScraperLog.logger.info 'INVOKED TASK: main_scrape_tasks:previous_month'

      Rake.application.invoke_task("scraper:update_proxy_list")
      Rake.application.invoke_task("scraper:scrape_ad_ids_posted_previous_month[#{args[:optional_number_months_ago]}]")
      Rake.application.invoke_task("scraper:scrape_ads_flagged_unscraped[true]")
      Rake.application.invoke_task('scraper:compress_html_copies')
      Rake.application.invoke_task("scraper:find_duplicates_previous_month[#{args[:optional_number_months_ago]}]")
      Rake.application.invoke_task("scraper:export_previous_month_ads_to_iset_csv[#{args[:optional_number_months_ago]}]")
      Rake.application.invoke_task('data:update_github')
    end

    desc "Perform scrape tasks on today's ads"
    task :today, [:optional_limit] do |_t, args|
      ScraperLog.logger.info 'INVOKED TASK: main_scrape_tasks:today'

      Rake.application.invoke_task("scraper:update_proxy_list")

      limit = clean_number_argument(args[:optional_limit])
      if limit.nil?
        Rake.application.invoke_task('scraper:scrape_ad_ids_posted_today')
      else
        Rake.application.invoke_task("scraper:scrape_ad_ids_posted_today[#{limit}]")
      end

      Rake.application.invoke_task('scraper:scrape_ads_flagged_unscraped[true]')
      Rake.application.invoke_task('scraper:compress_html_copies')

      today = Date.today.strftime('%Y-%m-%d')

      Rake.application.invoke_task(
        "scraper:export_ads_to_iset_csv[#{today}, #{today}, false]"
      )
    end
  end

  ########################################################################
  # Scrape ad ids, save as ads and mark them with has_unscraped_ad_entry #

  desc 'Update the list of proxies'
  task :update_proxy_list do
    ScraperLog.logger.info 'INVOKED TASK: update_proxy_list'
    Proxy.update_proxy_list
  end

  desc 'Scrape ad ids posted on place.ge today and flag for scraping'
  task :scrape_ad_ids_posted_today, [:optional_limit] do |_t, args|
    ScraperLog.logger.info 'INVOKED TASK: scrape_ad_ids_posted_today'
    limit = clean_number_argument(args[:optional_limit])

    PlaceGeAdGroup.new(Date.today, Date.today, limit)
      .run(&:scrape_and_save_ad_ids)
  end

  desc 'Scrape ad ids posted on place.ge yesterday and flag for scraping'
  task :scrape_ad_ids_posted_yesterday, [:optional_limit] do |_t, args|
    ScraperLog.logger.info 'INVOKED TASK: scrape_ad_ids_posted_yesterday'
    limit = clean_number_argument(args[:optional_limit])

    PlaceGeAdGroup.new(Date.today - 1, Date.today - 1, limit)
      .run(&:scrape_and_save_ad_ids)
  end

  desc 'Scrape ad ids posted within provided time period and flag for scraping; parameters should be in format [yyyy-mm-dd,yyyy-mm-dd]'
  task :scrape_ad_ids_posted_in_time_period, [:start_date, :end_date, :optional_limit] do |_t, args|
    ScraperLog.logger.info "INVOKED TASK: scrape_ad_ids_posted_in_time_period(#{args[:start_date]},#{args[:end_date]})"

    start_date = process_start_date(args[:start_date])
    end_date = process_end_date(args[:end_date])
    limit = clean_number_argument(args[:optional_limit])

    PlaceGeAdGroup.new(start_date, end_date, limit)
      .run(&:scrape_and_save_ad_ids)
  end

  desc 'Scrape ad ids posted in a previous month'
  task :scrape_ad_ids_posted_previous_month, [:optional_number_months_ago] do |_t, args|
    ScraperLog.logger.info "INVOKED TASK: scrape_ad_ids_posted_previous_month"

    months_ago = clean_number_argument(args[:optional_number_months_ago])
    months_ago = 1 if months_ago.nil?

    PlaceGeAdGroup.new(*previous_month_start_and_end_dates(Date.today, months_ago), nil)
      .scrape_and_save_ad_ids(true)
  end

  ########################################################################
  # Scrape ads that are marked has_unscraped_ad_entry #

  desc 'Scrape ad entries for ads in database that are flagged for scraping'
  task :scrape_ads_flagged_unscraped, [:with_hydra] do |_t, args|
    ScraperLog.logger.info 'INVOKED TASK: scrape_ads_flagged_unscraped'
    if args[:with_hydra].nil?
      PlaceGeAdGroup.new.run(&:scrape_and_save_unscraped_ad_entries)
    else
      PlaceGeAdGroup.new.run(&:scrape_and_save_unscraped_ad_entries_with_hydra)
    end
  end

  ########################################################################
  # Single ad tasks #

  desc 'Scrape place.ge real estate ad by id'
  task :scrape_and_output_ad, [:place_ge_ad_id] do |_t, args|
    if args[:place_ge_ad_id].nil?
      puts 'Error: Please provide a place.ge ad ID as an argument.'
      return
    end

    ad = PlaceGeAd.new(args[:place_ge_ad_id])
    ad.retrieve_page_and_save_html_copy
    ad.scrape_all
    puts ad.to_s
  end

  desc 'Open place.ge real estate ad in default browser'
  task :open_ad_in_browser, [:place_ge_ad_id] do |_t, args|
    if args[:place_ge_ad_id].nil?
      puts 'Please provide a place.ge ad ID as an argument.'
      return
    end

    ad = PlaceGeAd.new(args[:place_ge_ad_id])
    ad.open_in_browser
  end

  ########################################################################
  # CSV Export #

  desc "Export a previous month's ad data to CSV for analysis by ISET"
  task :export_previous_month_ads_to_iset_csv, [:optional_number_months_ago] do |_t, args|
    ScraperLog.logger.info 'INVOKED TASK: export_pervious_month_ads_to_iset_csv'

    months_ago = clean_number_argument(args[:optional_number_months_ago])
    months_ago = 1 if months_ago.nil?

    Ad.to_iset_csv(*previous_month_start_and_end_dates(Date.today, months_ago), false)
  end

  desc 'Output subset of ad data to CSV for analysis by ISET; parameters should be in format [yyyy-mm-dd,yyyy-mm-dd,with_duplicate(boolean)]'
  task :export_ads_to_iset_csv, [:start_date, :end_date, :with_duplicates] do |_t, args|
    with_duplicates = args[:with_duplicates].nil? ? true : args[:with_duplicates] == "false"
    ScraperLog.logger.info "INVOKED TASK: export_ads_to_iset_csv(#{args[:start_date]},#{args[:end_date]},#{with_duplicates})"

    start_date = process_start_date(args[:start_date])
    end_date = process_end_date(args[:end_date])

    Ad.to_iset_csv(start_date, end_date, with_duplicates)
  end

  desc 'Output info for ad ids to CSV'
  task :export_ad_ids_to_csv, [:ad_ids] do |_t, args|
    ids = args[:ad_ids].split('-')
    Ad.to_csv(ids)
  end

  ########################################################################
  # Compressing copies of ad entry HTML #

  desc 'Compresses all uncompressed .html files in system/place_ge_ads_html'
  task :compress_html_copies do
    ScraperLog.logger.info 'INVOKED TASK: compress_html_copies'

    uncompressed = Dir.glob(File.join('system', 'place_ge_ads_html', '*.html'))

    uncompressed.each do |file_name|
      puts "Compressing #{file_name}"
      compressed_name = "#{file_name}.tar.bz2"
      `tar -cvjSf #{compressed_name} #{file_name}`
      File.delete(file_name)
      puts "Finished compressing #{compressed_name}"
    end
  end

  ########################################################################
  # Find duplicate ad entries and mark one of them as the primary property

  desc 'Find duplicates for previous month'
  task :find_duplicates_previous_month, [:optional_number_months_ago] do |_t, args|
    ScraperLog.logger.info 'INVOKED TASK: find_duplicates_previous_month'

    months_ago = clean_number_argument(args[:optional_number_months_ago])
    months_ago = 1 if months_ago.nil?

    previous_month = (Date.today).prev_month(months_ago)

    AdEntry.identify_duplicates_for_month_year(
      previous_month.month,
      previous_month.year
    )
  end

  desc 'find duplicates for a given month and year'
  task :find_duplicates, [:month, :year] do |_t, args|
    ScraperLog.logger.info "INVOKED TASK: find_duplicates(#{args[:month]}, #{args[:year]})"

    AdEntry.identify_duplicates_for_month_year(args[:month], args[:year])
  end
end

namespace :data do
  desc "Add the files in the data directory to the data repo on github"
  task :update_github do
    ScraperLog.logger.info 'INVOKED TASK: data:update_github'

    update_data_github
  end
end
