$Cypress.register "Request", (Cypress, _, $) ->

  validHttpMethodsRe = /^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)$/

  isOptional = (memo, val, key) ->
    if _.isNull(val)
      memo.push(key)
    memo

  REQUEST_DEFAULTS = {
    url: ""
    method: "GET"
    qs: null
    body: null
    auth: null
    headers: null
    json: null
    form: null
    gzip: true
    followRedirect: true
  }

  REQUEST_PROPS = _.keys(REQUEST_DEFAULTS)

  OPTIONAL_OPTS = _.reduce(REQUEST_DEFAULTS, isOptional, [])

  request = (options) =>
    Cypress.triggerPromise("request", options)

  responseFailed = (err) ->
    err.triggerPromise is true

  argIsHttpMethod = (str) ->
    _.isString(str) and validHttpMethodsRe.test str.toUpperCase()

  isValidJsonObj = (body) ->
    _.isObject(body) and not _.isFunction(body)

  whichAreOptional = (val, key) ->
    val is null and key in OPTIONAL_OPTS

  # Cypress.extend
  #   ## set defaults for all requests?
  #   requestDefaults: (options = {}) ->

  Cypress.addParentCommand
    ## allow our signature to be similar to cy.route
    ## METHOD / URL / BODY
    ## or object literal with all expanded options
    request: (args...) ->
      options = o = {}

      switch
        when _.isObject(args[0])
          _.extend options, args[0]

        when args.length is 1
          o.url = args[0]

        when args.length is 2
          ## if our first arg is a valid
          ## HTTP method then set method + url
          if argIsHttpMethod(args[0])
            o.method = args[0]
            o.url    = args[1]
          else
            ## set url + body
            o.url    = args[0]
            o.body   = args[1]

        when args.length is 3
          o.method = args[0]
          o.url    = args[1]
          o.body   = args[2]

      _.defaults(options, REQUEST_DEFAULTS, {
        log: true
        timeout: Cypress.config("responseTimeout")
        failOnStatusCode: true
      })

      options.method = options.method.toUpperCase()

      if _.has(options, "failOnStatus")
        $Cypress.Utils.warning("The cy.request() 'failOnStatus' option has been renamed to 'failOnStatusCode'. Please update your code. This option will be removed at a later time.")
        options.failOnStatusCode = options.failOnStatus

      ## normalize followRedirects -> followRedirect
      ## because we are nice
      if _.has(options, "followRedirects")
        options.followRedirect = options.followRedirects

      if not validHttpMethodsRe.test(options.method)
        $Cypress.Utils.throwErrByPath("request.invalid_method", {
          args: { method: o.method }
        })

      if not options.url
        $Cypress.Utils.throwErrByPath("request.url_missing")

      if not _.isString(options.url)
        $Cypress.Utils.throwErrByPath("request.url_wrong_type")

      ## normalize the url by prepending it with our current origin
      ## or the baseUrl
      ## or just using the options.url if its FQDN
      ## origin may return an empty string if we haven't visited anything yet
      options.url = Cypress.Location.normalize(options.url)

      if originOrBase = @_getLocation("origin") or @Cypress.config("baseUrl")
        options.url = Cypress.Location.qualifyWithBaseUrl(originOrBase, options.url)

      ## if options.url isnt FQDN then we need to throw here
      ## if we made a request prior to a visit then it needs
      ## to be filled out
      if not Cypress.Location.isFullyQualifiedUrl(options.url)
        $Cypress.Utils.throwErrByPath("request.url_invalid")

      ## only set json to true if form isnt true
      ## and we have a valid object for body
      if options.form isnt true and isValidJsonObj(options.body)
        options.json = true

      options = _.omit(options, whichAreOptional)

      if a = options.auth
        if not _.isObject(a)
          $Cypress.Utils.throwErrByPath("request.auth_invalid")

      if h = options.headers
        if _.isObject(h)
          options.headers = h
        else
          $Cypress.Utils.throwErrByPath("request.headers_invalid")

      if not _.isBoolean(options.gzip)
        $Cypress.Utils.throwErrByPath("request.gzip_invalid")

      if f = options.form
        if not _.isBoolean(f)
          $Cypress.Utils.throwErrByPath("request.form_invalid")

      ## clone the requestOpts and reduce them down
      ## to the bare minimum to send to lib/request
      requestOpts = _(options).pick(REQUEST_PROPS)

      if options.log
        options._log = Cypress.Log.command({
          message: ""
          consoleProps: ->
            resp = options.response ? {}
            rr   = resp.allRequestResponses ? []

            obj = {}

            word = $Cypress.Utils.plural(rr.length, "Requests", "Request")

            ## if we have only a single request/response then
            ## flatten this to an object, else keep as array
            rr = if rr.length is 1 then rr[0] else rr

            obj[word] = rr
            obj["Returned"] = _.pick(resp, "status", "duration", "body", "headers")

            return obj

          renderProps: ->
            status = switch
              when r = options.response
                r.status
              else
                indicator = "pending"
                "---"

            indicator ?= if options.response?.isOkStatusCode then "successful" else "bad"

            {
              message: "#{options.method} #{status} #{_.truncate(options.url, 25)}"
              indicator: indicator
            }
        })

      ## need to remove the current timeout
      ## because we're handling timeouts ourselves
      @_clearTimeout()

      request(requestOpts)
      .timeout(options.timeout)
      .then (response) =>
        options.response = response

        ## bomb if we should fail on non okay status code
        if options.failOnStatusCode and response.isOkStatusCode isnt true
          $Cypress.Utils.throwErrByPath("request.status_invalid", {
            onFail: options._log
            args: {
              method:          requestOpts.method
              url:             requestOpts.url
              requestBody:     response.requestBody
              requestHeaders:  response.requestHeaders
              status:          response.status
              statusText:      response.statusText
              responseBody:    response.body
              responseHeaders: response.headers
              redirects:       response.redirects
            }
          })

        return response
      .catch Promise.TimeoutError, (err) =>
        $Cypress.Utils.throwErrByPath "request.timed_out", {
          onFail: options._log
          args: { timeout: options.timeout }
        }
      .catch responseFailed, (err) ->
        $Cypress.Utils.throwErrByPath("request.loading_failed", {
          onFail: options._log
          args: {
            error:   err.message
            stack:   err.stack
            method:  requestOpts.method
            url:     requestOpts.url
          }
        })
