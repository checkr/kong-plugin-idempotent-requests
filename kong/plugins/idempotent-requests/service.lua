local cjson = require("cjson.safe").new()
local http = require "kong.plugins.idempotent-requests.http.connect-better"
local pairs = pairs
local table = table
local tonumber = tonumber
local url = require "socket.url"

local api_v2_captures_path = "/api/v2/captures"

local function extract_headers(response_headers)
  local headers = {}
  for header_key, header_value in pairs(response_headers) do
    local header = {
      key = header_key,
      value = header_value
    }
    table.insert(headers, header)
  end
  return headers
end

local function allocate_capture_payload(idempotency_key)
  return cjson.encode({
    idempotency_key = idempotency_key
  })
end

local function record_capture_payload(idempotency_key, response_status, response_body, response_headers)
  local response = {
    response_status = response_status,
  }

  if response_body then
    response.response_body = response_body
  end

  response.response_headers = extract_headers(response_headers)

  return cjson.encode({
    idempotency_key = idempotency_key,
    response = response
  })
end

local function send_request(conf, request)

  local client = http.new()
  client:set_timeout(conf.timeout)

  local parsed_url = url.parse(conf.idempotent_requests_server_url)

  local ok, err = client:connect_better {
    scheme = parsed_url.scheme,
    host = parsed_url.host,
    port = tonumber(parsed_url.port),
  }

  if not ok then
    return nil, err
  end

  local res, err = client:request {
    method = request.method,
    path = api_v2_captures_path,
    body = request.payload
  }

  return res, err
end

local IdempotentRequestService = {}

local Request = { }
function Request:new(method, payload)
  local self = {}
  self.method = method
  self.payload = payload
  return self
end

-- A class static function to allocate capture for a given idempotency_key
function IdempotentRequestService.allocate_capture(conf, idempotency_key)
  local payload = allocate_capture_payload(idempotency_key)
  local request = Request:new("PUT", payload)
  return send_request(conf, request)
end

-- A class static function to record a capture for a given idempotency_key
function IdempotentRequestService.record_capture(conf, idempotency_key, status, body, headers)
  local payload = record_capture_payload(idempotency_key, status, body, headers)
  kong.log.inspect("record_capture_payload: ", payload)
  local request = Request:new("POST", payload)
  return send_request(conf, request)
end

-- return our service object
return IdempotentRequestService
