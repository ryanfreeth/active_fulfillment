require 'cgi'
require 'base64'

module ActiveFulfillment
  class NWFramingService < Service
    SERVICE_URLS = {
      fulfillment: 'https://%<login>s:%<password>s@www.nwframing.com/IFS%<test>s/api/%<role>s/OrderBody',
      inventory: 'https://%<login>s:%<password>s@www.nwframing.com/IFS%<test>s/api/%<role>s',
      tracking: 'https://%<login>s:%<password>s@www.nwframing.com/IFS%<test>s/api/%<role>s/OrderStatus/%<id>s'
    }.freeze

    # Pass in the login and password for the NWFraming account.
    # Optionally pass in the :test => true to force test mode
    def initialize(options = {})
      requires!(options, :login, :password, :role)

      super
    end

    def test_mode?
      true
    end

    def fulfill(order_id, shipping_address, line_items, options = {})
      # requires!(options, :billing_address)
      commit :fulfillment, build_fulfillment_request(order_id, shipping_address, line_items, options)
    end

    def fetch_stock_levels(options = {})
      commit :inventory, build_inventory_request(options)
    end

    def fetch_tracking_data(order_ids, _options = {})
      commit :tracking, build_tracking_request(order_ids)
    end

    private

    def build_fulfillment_request(order_id, shipping_address, line_items, _options)
      data = {
        OrderId: order_id,
        Destination: format_address(shipping_address),
        OrderItems: format_line_items(line_items)
      }
      data[:DutiesPaid] = 'true'
      data
    end

    def build_inventory_request(_options)
      {}
    end

    def commit(action, request)
      request = request.merge(test: test?)
      headers = build_headers
      endpoint = build_endpoint(action)
      data = ssl_post(endpoint, JSON.generate(request), headers)
      response = parse_response(data)
      Response.new(response['success'], 'message', response, test: response['test'])
    rescue ActiveUtils::ResponseError => e
      handle_error(e)
    rescue JSON::ParserError => e
      Response.new(false, e.message)
    end

    def get(action, request)
      request = request.merge(test: test?)
      headers = build_headers
      endpoint = build_endpoint(action)
      data = ssl_get(endpoint + '?' + request.to_query, headers)
      response = parse_response(data)
      Response.new(response['success'], 'message', response, test: response['test'])
    rescue ActiveUtils::ResponseError => e
      handle_error(e)
    rescue JSON::ParserError => e
      Response.new(false, e.message)
    end

    def parse_response(json)
      JSON.parse(json)
    end

    def handle_error(e)
      response = parse_error(e.response)
      Response.new(false, response[:http_message], response)
    end

    def parse_error(http_response)
      response = {}
      response[:http_code] = http_response.code
      response[:http_message] = http_response.message
      response
    end

    def format_address(address)
      data = {
        Name: address[:name],
        Address1: address[:address1],
        City: address[:city],
        State: address[:state],
        Country: address[:country],
        Postal: address[:zip].blank? ? '-' : address[:zip]
      }
      data[:ShipVia] = 'FedEx'
      data[:ShippingMethod] = 'Ground'

      data[:BillToName] = address[:company] unless address[:company].blank?
      data[:email] = address[:email] unless address[:email].blank?
      data[:Address2] = address[:address2] unless address[:address2].blank?
      data[:Phone] = address[:phone] unless address[:phone].blank?
      data
    end

    def format_line_items(items)
      data = []
      items.each_with_index do |item, index|
        data << {
          Quantity: item[:quantity],
          SKU: item[:sku],
          Description: item[:description],
          RetailPrice: item[:price],
          Images: format_image(item),
          ItemId: index
        }
      end
      data
    end

    def format_image(item)
      images = []
      images << {
        ImageID: item[:sku],
        URL: item[:url]
      }
    end

    def build_headers
      {
        'Authorization' => 'Basic ' + Base64.encode64(@options[:login] + ':' + @options[:password]),
        'User-Agent' => 'Ryan Freeth Fulfillment',
        'Content-Type' => 'application/json'
      }
    end

    def build_endpoint(action)
      test = @options[:test] ? '.Test' : ''
      format(SERVICE_URLS[action], login: CGI.escape(@options[:login]), password: @options[:password], role: @options[:role], test: test)
    end
  end
end
