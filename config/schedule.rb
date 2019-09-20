job_type :run_rake_task, 'cd :path && bundle exec rake :task --quiet'

# scrape last months data
every '0 01 14 * *' do
  run_rake_task 'scraper:main_scrape_tasks:previous_month'
end

# update the proxies every 30 mins when the scraper is running
every '*/30 * 14,15,16,17,18 * *' do
  run_rake_task 'scraper:update_proxy_list'
end
