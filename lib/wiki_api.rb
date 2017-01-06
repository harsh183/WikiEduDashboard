# frozen_string_literal: true
require 'mediawiki_api'
require 'json'
require "#{Rails.root}/lib/article_class_extractor"

#= This class is for getting data directly from the MediaWiki API.
class WikiApi
  def initialize(wiki = nil)
    wiki ||= Wiki.default_wiki
    @api_url = wiki.api_url
  end

  ################
  # Entry points #
  ################

  # General entry point for making arbitrary queries of a MediaWiki wiki's API
  def query(query_parameters)
    mediawiki('query', query_parameters)
  end

  def get_page_content(page_title)
    response = mediawiki('get_wikitext', page_title)
    response.status == 200 ? response.body : nil
  end

  def get_user_id(username)
    user_query = { list: 'users',
                   ususers: username }
    user_data = mediawiki('query', user_query)
    return unless user_data.data['users'].any?
    user_id = user_data.data['users'][0]['userid']
    user_id
  end

  def redirect?(page_title)
    response = get_page_info([page_title])
    return false if response.nil?
    redirect = response['pages']&.values&.dig(0, 'redirect')
    redirect ? true : false
  end

  def get_page_info(titles)
    query_params = { prop: 'info',
                     titles: titles }
    response = query(query_params)
    response.status == 200 ? response.data : nil
  end

  def get_article_rating(titles)
    titles = [titles] unless titles.is_a?(Array)
    titles = titles.sort_by(&:downcase)

    talk_titles = titles.map { |title| 'Talk:' + title }
    raw = get_raw_page_content(talk_titles)
    return [] unless raw

    # Pages that are missing get returned before pages that exist, so we cannot
    # count on our array being in the same order as titles.
    raw.map do |_article_id, talkpage|
      # Remove "Talk:" from the "title" value to get the title.
      { talkpage['title'][5..-1].tr(' ', '_') =>
        parse_article_rating(talkpage) }
    end
  end

  ###################
  # Parsing methods #
  ###################

  def parse_article_rating(raw_talk)
    # Handle MediaWiki API errors
    return nil if raw_talk.nil?
    # Handle the case of nonexistent talk pages.
    return nil if raw_talk['missing']

    wikitext = raw_talk['revisions'][0]['*']
    ArticleClassExtractor.new(wikitext).extract
  end

  #####################
  # Other API methods #
  #####################

  # Get raw page content for one or more pages titles, which can be parsed to
  # find the article ratings. (The corresponding Talk page are the one with the
  # relevant info.) Example query:
  # http://en.wikipedia.org/w/api.php?action=query&prop=revisions&rvprop=content&rawcontinue=true&redirects=true&titles=Talk:Selfie
  def get_raw_page_content(article_titles)
    query_parameters = { titles: article_titles,
                         prop: 'revisions',
                         rvprop: 'content' }
    info = mediawiki('query', query_parameters)
    return if info.nil?
    page = info.data['pages']
    page.nil? ? nil : page
  end

  ###################
  # Private methods #
  ###################
  private

  def mediawiki(action, query)
    tries ||= 3
    @mediawiki = api_client
    @mediawiki.send(action, query)
  rescue MediawikiApi::ApiError => e
    handle_api_error e, action, query
  rescue StandardError => e
    tries -= 1
    raise e unless typical_errors.include?(e.class)
    retry if tries >= 0
    Raven.capture_exception e, level: 'warning'
    return nil
  end

  def api_client
    MediawikiApi::Client.new @api_url
  end

  def handle_api_error(e, action, query)
    Rails.logger.warn "Caught #{e}"
    Raven.capture_exception e, level: 'warning',
                               extra: { action: action,
                                        query: query,
                                        api_url: @api_url }
    return nil # Do not return a Raven object
  end

  def typical_errors
    [Faraday::TimeoutError,
     Faraday::ConnectionFailed,
     MediawikiApi::HttpError]
  end
end
