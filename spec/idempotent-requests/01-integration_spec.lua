local helpers = require "spec.helpers"
local uuid = require "kong.tools.utils".uuid

local UPSTREAM_HOST = "test1.com"
local IDEMPOTENT_REQUESTS_SERVER_URL = "http://idempotent-requests-server:8080"

local PLUGIN_NAME = "idempotent-requests"


for _, strategy in helpers.all_strategies() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()

      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- Inject a test route. No need to create a service, there is a default
      -- service which will echo the request.
      local route = bp.routes:insert({
        hosts = { UPSTREAM_HOST },
        response_buffering = true,
      })
      -- add the plugin to test to the route we created
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          idempotent_requests_server_url = IDEMPOTENT_REQUESTS_SERVER_URL,
          timeout = 5000
        },
      }

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,
        -- write & load declarative config, only if 'strategy=off'
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("plugin", function()
      it("captures a response from the 1st request and returns it for the 2nd one", function()
        local idempotency_key_header = "Idempotency-Key"
        local idempotency_key = uuid()
        local extra_header = "X-Extra"
        local extra_header_value = "Potato"
        local exp_status = 200

        local r = client:get("/request", {
          headers = {
            host = UPSTREAM_HOST,
            [idempotency_key_header] = idempotency_key
          }
        })
        -- validate that the request succeeded, response status 200
        assert.response(r).has.status(exp_status)
        -- now check the request (as echoed by mockbin) to have the header
        local header_value = assert.request(r).has.header(idempotency_key_header)
        -- validate the value of that header
        assert.equal(idempotency_key, header_value)

        local r = client:get("/request", {
          headers = {
            host = UPSTREAM_HOST,
            [idempotency_key_header] = idempotency_key,
            [extra_header] = extra_header_value
          }
        })

        -- validate that the 2nd response has the same status
        assert.response(r).has.status(exp_status)
        -- now check the request (as echoed by mockbin) to have the same idempotency key header
        local header_value = assert.request(r).has.header(idempotency_key_header)
        -- validate the value of that header
        assert.equal(idempotency_key, header_value)
        -- now check the request (as echoed by mockbin) NOT to have the extra header
        assert.request(r).has_no.header(extra_header)

      end)
    end)

  end)
end
