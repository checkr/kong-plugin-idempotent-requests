local typedefs = require "kong.db.schema.typedefs"

-- Grab pluginname from module name
local plugin_name = ({ ... })[1]:match("^kong%.plugins%.([^%.]+)")

local schema = {
  name = plugin_name,
  fields = {
    -- the 'fields' array is the top-level entry with fields defined by Kong
    { consumer = typedefs.no_consumer }, -- this plugin cannot be configured on a consumer (typical for auth plugins)
    { protocols = typedefs.protocols_http },
    { config = {
      -- The 'config' record is the custom part of the plugin schema
      type = "record",
      fields = {
        { idempotent_requests_server_url = typedefs.url({ required = true }) },
        { idempotency_key_header_name = typedefs.header_name({ default = "Idempotency-Key" }) },
        { timeout = {
          type = "number",
          default = 30000
        } },
      },
    },
    },
  },
}

return schema
