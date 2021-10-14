local helpers = require "spec.helpers"
local PLUGIN_NAME = "awsplugin"

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()

      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- Inject a test route. No need to create a service, there is a default
      -- service which will echo the request.
      local route1 = bp.routes:insert({
        hosts = { "test1.com" },
      })
      -- add the plugin to test to the route we created
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          accessKeyId = "AKIASGVFEB7FJ6V34ZF3",
          secretAccessKey = "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",
          secret_arn = "nishiapikey",
          aws_service = "secretsmanager"

        },
      }

  
      -- start kong
      assert(helpers.start_kong({
        -- set the strategyo
        database   = strategy,
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
      if client then client:close() end
    end)

    describe("request", function()
      it("header has a missing cache_key config", function()
        local res = client:get("/request", {
          headers = {
            host = "test1.com",
            cookie = "asdasd;smsession=asdasdasd;user_directory=asdasd;canary=c1",
            --Authorization = "bearer at1"
          },
          -- body = {
          -- --   assertion = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMxMjMxMjMiLCJhdWQiOiJhdXRoZW50aWNhdGlvbi1zeXN0ZW0iLCJleHAiOiIxNjIwOTE0NDAwIiwibmFtZSI6Im5pc2hpMiIsImlzcyI6IlM3dzhkTERaTzBucmRHc29vQngyc1VwQzcyeWl6eEtwIiwiYWRtaW4iOnRydWUsIndlYlNob3BwZXJJRCI6IndlYnNob3A3IiwiaWF0IjoxNTE2MjM5MDIyLCJhc3NlcnRpb25faXNzdWVyIjoibmlzaGlfbm9yZHN0cm9tIiwic2hvcHBlcklEIjoic2hvcDciLCJOQ09NX0lEIjoiaWQ3In0.D5ucTQpoBjy95cbv8Yi5cWImd_Q23PRzL2XwB4et_4h5HbMooPKpl9jseWn0mVZIBwEwVTHme2YVI0PAsdGvvC4txdYJSGeSvGq6Yq3TuNo0i-s13bblOrTU3n4z5QAVWPvv2Tual-medomVfeZ-7DccLtqYm3f6r-qiMPl8b1lm5gCkxHQQnIgpaiNBaV3WzW_--NerGeFqHLBFMbYdtTDgZHSlkSxeyU9Pd5RBn7fG5JX967-robupjbgW9-NbRjiOAX7efpusWeb5jiXTetKErW_ujTiPq8F5lM6wtSPSwNrtUvuqHHki-on7ke8adKD5rUD6GGCXUeW73oGEEaF10fp-JM82q5L5aZcJiJR3Yl75Hfa3a6CU2DlfBh9KgQ0CMrALtY241z2wDVTcL1CDD9hLcjnh3u370BHqqtnZIL1brW93nPJ3C3xBTgqczl8I8Ipm_zvM18PkuBd4hHP_twAr5N2xpy_Sw-8MgmfCwsqLhHjcGt4Z9pcbiar4YL_IczxL2nRvnkSWdInpHNy3UgkNROJ-aEnxiojMW71WBH5ZhdSKGmtxOV3joDj_q4_FuDvN0WfMN6SfqdgRExCytCqqhekmBbaJHAMjJ2eFriCeizx7BPSee5yPJvzSTalUEK6qKEFJyV_ss5NefWf6gltmKEhSf61uvOlHr0k",
          -- --   grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer",
          -- --   --grant_type = "refresh_token",
          -- --   refresh_token = "y0ADZdzRqnWozNbUlIOnkE9W6813cVOM"
          -- }
        })

        local body = assert.response(res).has.status(401)
        print(body)
      end)
    end)

    describe("request", function()
      it(" has params as smsession but smsession missing as a cookie attribute ", function()
        local res = client:get("/request", {
          headers = {
            host = "test1.com",
            cookie = "asdasd;user_directory=asdasd;canary=c1",
            --Authorization = "bearer at1"
          },
          -- body = {
          -- --   assertion = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMxMjMxMjMiLCJhdWQiOiJhdXRoZW50aWNhdGlvbi1zeXN0ZW0iLCJleHAiOiIxNjIwOTE0NDAwIiwibmFtZSI6Im5pc2hpMiIsImlzcyI6IlM3dzhkTERaTzBucmRHc29vQngyc1VwQzcyeWl6eEtwIiwiYWRtaW4iOnRydWUsIndlYlNob3BwZXJJRCI6IndlYnNob3A3IiwiaWF0IjoxNTE2MjM5MDIyLCJhc3NlcnRpb25faXNzdWVyIjoibmlzaGlfbm9yZHN0cm9tIiwic2hvcHBlcklEIjoic2hvcDciLCJOQ09NX0lEIjoiaWQ3In0.D5ucTQpoBjy95cbv8Yi5cWImd_Q23PRzL2XwB4et_4h5HbMooPKpl9jseWn0mVZIBwEwVTHme2YVI0PAsdGvvC4txdYJSGeSvGq6Yq3TuNo0i-s13bblOrTU3n4z5QAVWPvv2Tual-medomVfeZ-7DccLtqYm3f6r-qiMPl8b1lm5gCkxHQQnIgpaiNBaV3WzW_--NerGeFqHLBFMbYdtTDgZHSlkSxeyU9Pd5RBn7fG5JX967-robupjbgW9-NbRjiOAX7efpusWeb5jiXTetKErW_ujTiPq8F5lM6wtSPSwNrtUvuqHHki-on7ke8adKD5rUD6GGCXUeW73oGEEaF10fp-JM82q5L5aZcJiJR3Yl75Hfa3a6CU2DlfBh9KgQ0CMrALtY241z2wDVTcL1CDD9hLcjnh3u370BHqqtnZIL1brW93nPJ3C3xBTgqczl8I8Ipm_zvM18PkuBd4hHP_twAr5N2xpy_Sw-8MgmfCwsqLhHjcGt4Z9pcbiar4YL_IczxL2nRvnkSWdInpHNy3UgkNROJ-aEnxiojMW71WBH5ZhdSKGmtxOV3joDj_q4_FuDvN0WfMN6SfqdgRExCytCqqhekmBbaJHAMjJ2eFriCeizx7BPSee5yPJvzSTalUEK6qKEFJyV_ss5NefWf6gltmKEhSf61uvOlHr0k",
          -- --   grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer",
          -- --   --grant_type = "refresh_token",
          -- --   refresh_token = "y0ADZdzRqnWozNbUlIOnkE9W6813cVOM"
          -- }
        })

        local body = assert.response(res).has.status(401)
        print(body)
      end)
    end)

    describe("request", function()
      it(" has params as user_dir but user_dir missing as a cookie attribute ", function()
        local res = client:get("/request", {
          headers = {
            host = "test1.com",
            cookie = "asdasd;smsession=asdasd;canary=c1",
            --Authorization = "bearer at1"
          },
          -- body = {
          -- --   assertion = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMxMjMxMjMiLCJhdWQiOiJhdXRoZW50aWNhdGlvbi1zeXN0ZW0iLCJleHAiOiIxNjIwOTE0NDAwIiwibmFtZSI6Im5pc2hpMiIsImlzcyI6IlM3dzhkTERaTzBucmRHc29vQngyc1VwQzcyeWl6eEtwIiwiYWRtaW4iOnRydWUsIndlYlNob3BwZXJJRCI6IndlYnNob3A3IiwiaWF0IjoxNTE2MjM5MDIyLCJhc3NlcnRpb25faXNzdWVyIjoibmlzaGlfbm9yZHN0cm9tIiwic2hvcHBlcklEIjoic2hvcDciLCJOQ09NX0lEIjoiaWQ3In0.D5ucTQpoBjy95cbv8Yi5cWImd_Q23PRzL2XwB4et_4h5HbMooPKpl9jseWn0mVZIBwEwVTHme2YVI0PAsdGvvC4txdYJSGeSvGq6Yq3TuNo0i-s13bblOrTU3n4z5QAVWPvv2Tual-medomVfeZ-7DccLtqYm3f6r-qiMPl8b1lm5gCkxHQQnIgpaiNBaV3WzW_--NerGeFqHLBFMbYdtTDgZHSlkSxeyU9Pd5RBn7fG5JX967-robupjbgW9-NbRjiOAX7efpusWeb5jiXTetKErW_ujTiPq8F5lM6wtSPSwNrtUvuqHHki-on7ke8adKD5rUD6GGCXUeW73oGEEaF10fp-JM82q5L5aZcJiJR3Yl75Hfa3a6CU2DlfBh9KgQ0CMrALtY241z2wDVTcL1CDD9hLcjnh3u370BHqqtnZIL1brW93nPJ3C3xBTgqczl8I8Ipm_zvM18PkuBd4hHP_twAr5N2xpy_Sw-8MgmfCwsqLhHjcGt4Z9pcbiar4YL_IczxL2nRvnkSWdInpHNy3UgkNROJ-aEnxiojMW71WBH5ZhdSKGmtxOV3joDj_q4_FuDvN0WfMN6SfqdgRExCytCqqhekmBbaJHAMjJ2eFriCeizx7BPSee5yPJvzSTalUEK6qKEFJyV_ss5NefWf6gltmKEhSf61uvOlHr0k",
          -- --   grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer",
          -- --   --grant_type = "refresh_token",
          -- --   refresh_token = "y0ADZdzRqnWozNbUlIOnkE9W6813cVOM"
          -- }
        })

        local body = assert.response(res).has.status(401)
        print(body)
      end)
    end)

    describe("request", function()
      it("header has expected correct values", function()
        local res = client:get("/request", {
          headers = {
            host = "test1.com",
            cookie = "asdasd;smsession=asdasdasd;user_directory=asdasd;canary=c1",
            Authorization = "bearer at1"
          },
          -- body = {
          -- --   assertion = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMxMjMxMjMiLCJhdWQiOiJhdXRoZW50aWNhdGlvbi1zeXN0ZW0iLCJleHAiOiIxNjIwOTE0NDAwIiwibmFtZSI6Im5pc2hpMiIsImlzcyI6IlM3dzhkTERaTzBucmRHc29vQngyc1VwQzcyeWl6eEtwIiwiYWRtaW4iOnRydWUsIndlYlNob3BwZXJJRCI6IndlYnNob3A3IiwiaWF0IjoxNTE2MjM5MDIyLCJhc3NlcnRpb25faXNzdWVyIjoibmlzaGlfbm9yZHN0cm9tIiwic2hvcHBlcklEIjoic2hvcDciLCJOQ09NX0lEIjoiaWQ3In0.D5ucTQpoBjy95cbv8Yi5cWImd_Q23PRzL2XwB4et_4h5HbMooPKpl9jseWn0mVZIBwEwVTHme2YVI0PAsdGvvC4txdYJSGeSvGq6Yq3TuNo0i-s13bblOrTU3n4z5QAVWPvv2Tual-medomVfeZ-7DccLtqYm3f6r-qiMPl8b1lm5gCkxHQQnIgpaiNBaV3WzW_--NerGeFqHLBFMbYdtTDgZHSlkSxeyU9Pd5RBn7fG5JX967-robupjbgW9-NbRjiOAX7efpusWeb5jiXTetKErW_ujTiPq8F5lM6wtSPSwNrtUvuqHHki-on7ke8adKD5rUD6GGCXUeW73oGEEaF10fp-JM82q5L5aZcJiJR3Yl75Hfa3a6CU2DlfBh9KgQ0CMrALtY241z2wDVTcL1CDD9hLcjnh3u370BHqqtnZIL1brW93nPJ3C3xBTgqczl8I8Ipm_zvM18PkuBd4hHP_twAr5N2xpy_Sw-8MgmfCwsqLhHjcGt4Z9pcbiar4YL_IczxL2nRvnkSWdInpHNy3UgkNROJ-aEnxiojMW71WBH5ZhdSKGmtxOV3joDj_q4_FuDvN0WfMN6SfqdgRExCytCqqhekmBbaJHAMjJ2eFriCeizx7BPSee5yPJvzSTalUEK6qKEFJyV_ss5NefWf6gltmKEhSf61uvOlHr0k",
          -- --   grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer",
          -- --   --grant_type = "refresh_token",
          -- --   refresh_token = "y0ADZdzRqnWozNbUlIOnkE9W6813cVOM"
          -- }
        })

        local body = assert.response(res).has.status(200)
        print(body)
      end)
    end)

  end)
end
