
  local plugin = {
    PRIORITY = 1005, -- set the plugin priority based on where this custom plugin should execute in the overall flow. Pre-function should run highest priority
    VERSION = "0.1",
  }

local kong = kong
local escape_uri = ngx.escape_uri
local cjson = require("cjson.safe").new()
local http = require "resty.http"
local sha = require "resty.sha256"
local base64 = require "ngx.base64"
local lrucache = require "resty.lrucache"   -- to introduce LRU lua memory caching 
local lru, err = lrucache.new(1000)  -- allow up to 1000 items in the cache


local kong_utils = require "kong.tools.utils"
local uuid = kong_utils.uuid
--local random_string = kong_utils.random_string
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"
local kong = kong
local AWS = require("resty.aws")
local aws = AWS:new()

local request_id

if not lru then
    error("failed to create the cache: " .. (err or "unknown"))
end

local function connect_to_dynamodb(plugin_conf)
  -- instantiate a service (optionally overriding the global config)
  local my_creds = aws:Credentials {
    accessKeyId = plugin_conf.accessKeyId,    -- captures the accessKeyId to connect with AWS services
    secretAccessKey = plugin_conf.secretAccessKey,  -- captures the secretAccessKey to connect with AWS
   }
     aws.config.credentials = my_creds
  local test_env = kong.request.get_header('x-pongotest-env')
  -- if test_env and test_env == 'local-dev' then
  --   return aws:DynamoDB {
  --     region = region,
  --     tls = false
  --   }
  -- end
  return aws:DynamoDB {
     region = plugin_conf.region
  }
end

local function get_item_by_access_token(current_token, tablename, dynamodb)
  local access_token_getitem = {
     Key = {
        id = {
           S = current_token
        }
     },
     TableName = tablename,
     ReturnConsumedCapacity = "TOTAL"
  }
  local item, err = dynamodb:getItem(access_token_getitem) -- to check if the hashedvalue items already exist
  kong.log.info("current token from db=", cjson.encode(item))
  -- kong.log.inspect(err)

  if err then
     local error = "Error fetching refresh token from DynamoDB. Error=" .. tostring(err)
     kong.log.err(error)
     return nil, error
  end

  if (not item)  or (not item.body) then
    kong.log.err("Error fetching refresh token from Database. Nil response from DynamoDB.")
    return nil, "Error fetching refresh token from Database. Nil response from DynamoDB."
  end

  if item.status ~= 200 then
    local error = "Error fetching access token from Database. Non 200 response code received. Status=" ..
    (item.status or '') .. " . Reason=" .. (item.reason or '')
    kong.log.err(error)
    return nil, error
  end
  if not item.body.Item then 
    kong.log.info("No Item returned in the body from Get operation. Send 404 back!. Response from dynamodb = ", cjson.encode(item.body))
    return kong.response.exit(404, {message = "Item not found in the table!"})
  else
    kong.log.info("item returned form dyamodb = ",cjson.encode(item))
    return item.body
  end
end


local function get_hashedjwt_from_db(hashvalue, dynamodb)
  local hashedvalue_getitem = {
     Key = {
        hashedvalue = {
           S = hashvalue
        }
     },
     TableName = "nosa-jwt-hashes",
     ReturnConsumedCapacity = "TOTAL"
  }
  local item, err = dynamodb:getItem(hashedvalue_getitem) -- to check if the hashedvalue items already exist
  kong.log.info("current token from db=", item)
  -- kong.log.inspect(err)

  if err then
     local error = "Error fetching refresh token from DynamoDB. Error=" .. tostring(err)
     kong.log.err(error)
     return nil, error
  end

  if (not item)  or (not item.body) then
     kong.log.err("Error fetching refresh token from Database. Nil response from DynamoDB.")
     return nil, "Error fetching refresh token from Database. Nil response from DynamoDB."
  end

  if item.status ~= 200 then
    local error = "Error fetching access token from Database. Non 200 response code received. Status=" ..
    (item.status or '') .. " . Reason=" .. (item.reason or '')
    kong.log.err(error)
    return nil, error
  end

  if not item.body.Item then
    return kong.response.exit(404, {message = "Item not found"})
  else
     return item.body.Item
  end
end


local function connect_to_secretsmanager(plugin_conf)
  local my_creds
  if plugin_conf.accessKeyId and plugin_conf.secretAccessKey then
    my_creds = aws:Credentials {
    accessKeyId = plugin_conf.accessKeyId,    -- captures the accessKeyId to connect with AWS services
    secretAccessKey = plugin_conf.secretAccessKey,  -- captures the secretAccessKey to connect with AWS
   }
  
    aws.config.credentials = my_creds
  end
  -- instantiate a service (optionally overriding the global config)
  return aws:SecretsManager {
    type = "aws-sm",
    region = plugin_conf.region,

  }

end


-- Dump function allows us to look at the value of any objet, field or results
local dump = function(...)
  local info = debug.getinfo(2) or {}
  local input = { n = select("#", ...), ...}
  local write = require("pl.pretty").write
  local serialized
  if input.n == 1 and type(input[1]) == "table" then
    serialized = "(" .. type(input[1]) .. "): " .. write(input[1])
  elseif input.n == 1 then
    serialized = "(" .. type(input[1]) .. "): " .. tostring(input[1]) .. "\n"
  else
    local n
    n, input.n = input.n, nil
    serialized = "(list, #" .. n .. "): " .. write(input)
  end

  print(ngx.WARN,
          "\027[31m\n",
          "function '", tostring(info.name), ":" , tostring(info.currentline),
          "' in '", tostring(info.short_src), "' wants you to know:\n",
          serialized,
          "\027[0m")
end

local function getsecretfromaws(plugin_conf)
  local secretvalue
  if (plugin_conf.accessKeyId) and (plugin_conf.secretAccessKey) then
    kong.log.info("accesskeyId and secretAccessKey found in config. accessKeyId = ", plugin_conf.accessKeyId, " secretAccessKey = ",plugin_conf.secretAccessKey, " region = ", plugin_conf.region)
  else
    kong.log.info("No accessKeyid and secretAccessKey in plugin config!")
  end

  local secretkey = kong.request.get_header("secretkey")
  if (not secretkey) or (secretkey == "") then
    kong.log.err("incoming request does not have a secretkey specified in the header! Throwing 400 error")
    return kong.response.exit(400, {message = "Invalid Request. Does either not contain secretkey in the header or its invalid value!",})
  else
    kong.log.info("secret_arn = ",plugin_conf.secret_arn," which is present in the header and therefore valid request will proceed to call AWS SM!")
    local sm, err = connect_to_secretsmanager(plugin_conf)

    if err or (not sm) then  -- AWS connection is not successful
      kong.log.err("Error connecting to AWS SecretManager. Error = ", err)
      return kong.response.exit(500, {message = "Unable to connenct with AWS secrets manager service!"})
    else                    -- AWS connection is successful
      kong.log.info("Successful connection to AWS SecretManager!!")
      local clientid_param = {
        SecretId = secretkey,
        VersionStage = "AWSCURRENT"
          }
      kong.log.info("paramters = ", cjson.encode(clientid_param))
      local id_data,err = sm:getSecretValue(clientid_param)
      if err or (not id_data) then
        kong.log.err("Error received when calling getSecretsValue. Error = ",err)
        return kong.response.exit(500, {message = "Error calling SecretManager to get secret value"})
      elseif id_data.status ~= 200 then
        kong.log.err("AWS SecrectsManager sent a non-200 response. Status = ",id_data.status, " reason = ", id_data.reason, " message = ", cjson.encode(id_data.body), plugin_conf.client_id_arn)
        return kong.response.exit(404, {message ="Specified Secret not found in AWS SecretsManager"})
      else    -- happy path scenario for successful AWS call
        kong.log.info("data received from AWS SecretManager = ",cjson.encode(id_data))
        secretvalue = id_data.body.SecretString
      end
    end   -- end to else condition when AWS connection is successful 
  end  -- end to else condition where client_id_arn and client_secret_arn are valid 

    return secretvalue
end -- end of function getsecretfromaws



function plugin:access(plugin_conf)

  local requestpath = kong.request.get_path()  -- get the path on which request is sent
  kong.log.info("incoming request path = ", requestpath)
  local access_token_response, tablename, dynamodb
  -- code below checks if the incoming requst is for AWS SM or AWS dynamodb service

  if plugin_conf.aws_service == "dynamodb" then
    kong.log.info("Request comes for dynamodb operation")
    -- TODO need to add logic to call dynamodb service here
    tablename = kong.request.get_header("tablename")
    kong.log.info("Table name = ",tablename)
    if not tablename or (tablename == "") then 
      return kong.response.exit(400, {message = "Table name missing in the request. Please correct it and retry!"})
    end

    --return kong.response.exit(502, {message = "Dynamodb still under construction!"})
    dynamodb, err = connect_to_dynamodb(plugin_conf)
      if err or (not dynamodb) then
         kong.log.err("failed to connect to dynamodb", err)
         return kong.response.exit(500, {message = "Failed to connect to dynamodb. Error: " .. err }) -- TODO: check why would this return nil. probably it has to exit with kong.response.exit()
      else
        kong.log.debug("Connected to dynamoDB successfully!")
         --TODO Actual code logic goes here
        if not kong.request.get_header("key") or (kong.request.get_header("key") == "") then 
          kong.log.err("missing mandatory field key in the request. Throwing 400 error back to client!")
          return kong.response.exit(400, {message = "Table key for lookup is missing from Request Header. Please correct it and try again!"})
        end

        access_token_response, err = get_item_by_access_token(kong.request.get_header("key"), tablename, dynamodb)
        if err or (not access_token_response) then
          kong.log.err("Error occured when trying to GET item from dynamodb. Error = ",err)
          return kong.response.exit(500, {error = "API ran into an unexpected error. Please retry in sometime or call customer service!"})
        elseif access_token_response.count == 0 then
          kong.log.warn("access_token_response.body.count = ", access_token_response.count)
          return kong.response.exit(404, {message = "No item found in the the table for specified key. Please try again with a different key! "})
        else
          return kong.response.exit(200, access_token_response.Item)
        end
      end

  elseif plugin_conf.aws_service == "secretsmanager" then
    kong.log.info("Request is not coming from AWS SM")

    local indexstart, indexend, ustart, uend 
    local secret_value, client_secret_temp    
    secret_value = getsecretfromaws(plugin_conf)
    kong.log.info("secret value extracted from AWS SM = ",secret_value)

    if not secret_value then
      return kong.response.exit(404, {message = "No Secret value found!"})
    else
      return kong.response.exit(200, {secret = secret_value})
    end
  
  else
    kong.log.warn("value of aws service not valid from enum list. Throw 400 error")
    return kong.response.exit(400, {message = "Invalid value of AWS Service ", plugin_conf.aws_service})
  end   -- end of if condition check on type of AWS service to be invoked
  
end 
-- return plugin object
return plugin