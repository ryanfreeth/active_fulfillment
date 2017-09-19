require 'cgi'
require 'base64'

module ActiveFulfillment
  class NWFramingService < Service
    SERVICE_URLS = {
      fulfillment: 'https://www.nwframing.com/IFS%<test>s/api/%<role>s/OrderBody',
      inventory: 'https://www.nwframing.com/IFS%<test>s/api/%<role>s',
      tracking: 'https://www.nwframing.com/IFS%<test>s/api/%<role>s/OrderStatus/%<id>s'
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

    def build_fulfillment_request(order_id, shipping_address, line_items, options)
      data = {
        OrderId: order_id.to_s,
        Destination: format_address(shipping_address),
        OrderItems: format_line_items(line_items)
      }
      data[:DutiesPaid] = 'true'
      data[:SpecialInstructions] = options.special_instructions
      data
    end

    def build_inventory_request(_options)
      {}
    end

    def commit(action, request)
      headers = build_headers
      endpoint = build_endpoint(action)
      data = ssl_post(endpoint, JSON.generate(request), headers)
      response = parse_response(data)
      Response.new('success', '200', {})
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
      Response.new(response[0], '200', response)
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

    def format_address(shipping_address)
      data = {}
      address = {
        Name: shipping_address[:name],
        Address1: shipping_address[:address1],
        City: shipping_address[:city],
        State: shipping_address[:state],
        Country: shipping_address[:country],
        Postal: shipping_address[:zip].blank? ? '-' : shipping_address[:zip]
      }
      data[:Address] = address
      data[:ShipVia] = 'FedEx'
      data[:ShippingMethod] = 'Ground'

      data[:Address][:BillToName] = shipping_address[:company] unless shipping_address[:company].blank?
      data[:Address][:email] = shipping_address[:email] unless shipping_address[:email].blank?
      data[:Address][:Address2] = shipping_address[:address2] unless shipping_address[:address2].blank?
      data[:Address][:Phone] = shipping_address[:phone] unless shipping_address[:phone].blank?
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
          ItemId: (index + 1).to_s
        }
      end
      data
    end

    def format_image(item)
      images = []
      images << {
        ImageID: item[:title],
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
      format(SERVICE_URLS[action], role: @options[:role], test: test)
    end
  end
end
