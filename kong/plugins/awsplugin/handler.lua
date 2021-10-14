
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

if not lru then
    error("failed to create the cache: " .. (err or "unknown"))
end

local AWS = require("resty.aws")
-- or similarly
local aws = AWS:new()

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
  if (plugin_conf.accessKeyId) and (plugin_conf.secretAccessKey) then
    kong.log.info("accesskeyId and secretAccessKey found in config. accessKeyId = ", plugin_conf.accessKeyId, " secretAccessKey = ",plugin_conf.secretAccessKey, " region = ", plugin_conf.region)
  else
    kong.log.info("No accessKeyid and secretAccessKey in plugin config!")
  end

   client_id_temp = kong.request.get_header("secretkey")
  if (not client_id_temp) or (client_id_temp == "") then
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
        SecretId = client_id_temp,
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
        client_id_value = id_data.body.SecretString
      end
    end   -- end to else condition when AWS connection is successful 
  end  -- end to else condition where client_id_arn and client_secret_arn are valid 

    return client_id_value
end -- end of function getsecretfromaws



function plugin:access(plugin_conf)

  local requestpath = kong.request.get_path()  -- get the path on which request is sent
  kong.log.info("incoming request path = ", requestpath)

  -- code below checks if the incoming requst is for AWS SM or AWS dynamodb service

  if plugin_conf.aws_service == "dynamodb" then
    kong.log.info("Request comes for dynamodb operation")
    -- TODO need to add logic to call dynamodb service here
  elseif plugin_conf.aws_service == "secretsmanager" then
    kong.log.info("Request is not coming from AWS SM")

    local indexstart, indexend, ustart, uend 
    local secret_value, client_secret_temp    
    local client_id_arn = plugin_conf.client_id_arn
    local client_secret_arn = plugin_conf.client_secret_arn 
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


  local function hashing(input)
    kong.log.info("key to be hashed = ",input)
  
    if (not input) or input == "" then
      kong.log.err("invalid input value = ",input)
      return nil
    end
    local hash = sha:new()
    hash:update(input) -- returns true or false
    local digest_mid = hash:final() -- to return the hashed value of assertion
    local digest_base64 = base64.encode_base64url(digest_mid)
    kong.log.info("hashed value of ",input," is ",digest_base64) -- check the final hashed value generated
    return digest_base64
  end 

  local function getAuthorizationToken()
    local authorization = kong.request.get_header("Authorization") -- token is passed as Authorization header
    if not authorization or authorization == "" then
      kong.log.err("Authorization header missing in request")
      return kong.response.exit(401, {message = "Missing or invalid Credentials!"})
    end

    local lowercase_auth = authorization:lower()
    local _, end_indx, _ = lowercase_auth:find("^%s*bearer%s+")
    local access_token = string.sub(authorization, end_indx+1) -- to extract the value of opaque token from header by trimming off "bearer"
    --kong.log.info("trimmed Authorization value =",access_token)
    if (not access_token) or access_token == "" then
      kong.log.err("trimmed access_token is nil!")
      return nil
    end
    return access_token
  end -- end of getAuthorizationToken method
end 
-- return plugin object
return plugin