local typedefs = require "kong.db.schema.typedefs"

-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

local schema = {
  name = plugin_name,
  fields = {
    -- the 'fields' array is the top-level entry with fields defined by Kong
    { consumer = typedefs.no_consumer },  -- this plugin cannot be configured on a consumer (typical for auth plugins)
    { protocols = typedefs.protocols_http },
    { config = {
        -- The 'config' record is the custom part of the plugin schema
        type = "record",
        fields = {
          -- a standard defined field (typedef), with some customizations
              { region = { -- plugin will use this value to connect with AWS services in the specified region
              type = "string",
              default = "us-east-2", -- specifies the value of region
              required = true,}},
              { accessKeyId = { -- user provides the accessKeyId to connect with AWS services. This wont be needed if Kong is running over EC2 instances
              type = "string",
              required = false,
              default = "change-me"
              }},
              { secretAccessKey = { -- user provides the secretAccessKey to connect with AWS services. This wont be needed if Kong is running over EC2 instances
              type = "string",
              required = false,
              default = "change-me"
              }},
              { aws_service = {.  -- option to select which AWS service should be called in this plugin. Current listed only dynamodb + secretsmanager but will open up to more in future
                type = "string",
                required = true,
                default = "secretsmanager",
                one_of = {
                  "dynamodb",
                  "secretsmanager"
                }
              }},
        },
      },
    },
  },
}

return schema
