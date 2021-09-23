local base64 = require "ngx.base64"
local cjson = require("cjson.safe").new()
local irs = require "kong.plugins.idempotent-requests.service"
local kong = kong

local function read_json_body(body)
  if body then
    return cjson.decode(body)
  end
end

local function headers_table(captured_headers)
  local headers = {}
  for i, header in ipairs(captured_headers) do
    headers[header.key] = header.value
  end
  return headers
end

local IdempotentRequestService = {
  PRIORITY = 1000, -- TODO set the plugin priority, which determines plugin execution order
  VERSION = "0.1",
}

function IdempotentRequestService:access(plugin_conf)

  local idempotency_key_raw = kong.request.get_header(plugin_conf.idempotency_key_header_name)

  if idempotency_key_raw then
    local idempotency_key = base64.encode_base64url(idempotency_key_raw)
    kong.log.debug("Idempotency Key: ", idempotency_key_raw, " base64url encoded: <", idempotency_key, ">")
    local allocation, err = irs.allocate_capture(plugin_conf, idempotency_key)

    if not allocation then
      kong.log.err("failed to allocate capture: ", err)
      return kong.response.exit(500, { message = "An unexpected error occurred" })
    end

    if allocation.status == 200 then
      kong.log.info("Found a previous capture. Idempotency Key: ", idempotency_key_raw)
      local capture = read_json_body(allocation:read_body())
      local headers = headers_table(capture.response.response_headers)
      kong.log.warn("headers are valid")
      return kong.response.exit(capture.response.response_status, capture.response.response_body, headers)
    elseif allocation.status == 202 then
      kong.log.info("Allocated a new capture. Idempotency Key: ", idempotency_key_raw)
      return
    elseif allocation.status == 409 then
      return kong.response.exit(409, { message = "Another request with the same idempotency key is in progress" })
    end

    return kong.response.exit(allocation.status, allocation:read_body())

  end
end

function IdempotentRequestService:response(plugin_conf)

  local idempotency_key_raw = kong.request.get_header(plugin_conf.idempotency_key_header_name)

  if idempotency_key_raw then
    local idempotency_key = base64.encode_base64url(idempotency_key_raw)
    local allocation, err = irs.record_capture(plugin_conf, idempotency_key, kong.response.get_status(), kong.service.response.get_raw_body(), kong.response.get_headers())

    if not allocation then
      kong.log.err("failed to record capture: ", err)
      return kong.response.exit(500, { message = "An unexpected error occurred" })
    end

    if allocation.status ~= 200 then
      kong.log.err("failed to record capture. Status: ", allocation.status, " Response: ", allocation:read_body())
      return kong.response.exit(500, { message = "An unexpected error occurred" })
    end

    kong.log.info("Recorded a new capture. Idempotency Key: ", idempotency_key_raw)

    return
  end
  return
end

-- return our plugin object
return IdempotentRequestService
