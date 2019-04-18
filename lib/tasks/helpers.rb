def clean_number_argument(unclean_number)
  return nil if unclean_number.nil?
  return nil unless unclean_number =~ /[[:digit:]]/
  unclean_number.to_i
end

def process_start_date(start_date)
  ScraperLog.logger.error 'Please provide a start date' if start_date.nil?
  begin
    Date.strptime(start_date, '%Y-%m-%d')
  rescue StandardError
    ScraperLog.logger.error 'Start date cannot be parsed'
    fail
  end
end

def process_end_date(end_date)
  ScraperLog.logger.error 'Please provide an end date' if end_date.nil?
  begin
    Date.strptime(end_date, '%Y-%m-%d')
  rescue StandardError
    ScraperLog.logger.error 'End date cannot be parsed'
    fail
  end
end

def previous_month_start_and_end_dates(date, number_months=1)
  start_date = date.prev_month(number_months).at_beginning_of_month
  end_date = date.prev_month(number_months).at_end_of_month

  [start_date, end_date]
end

