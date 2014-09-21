define [
	'jquery'
	'lodash'
	'json'
	'cookies'
	'moment'
	'od_config'
	'od_session'
	'od_data'
], ($, _, json, C, M, config, Session, D) ->

	# Dump the given arguments or log them to console
	log = ->
		try
			dump "#{x}\n" for x in arguments
			return
		catch
			console.log arguments
			return
	
	$notify = $ {}

	logError = (jqXHR, textStatus, errorThrown) ->
		log "#{textStatus} #{jqXHR.status} #{errorThrown}"
		$notify.trigger 'od.fail', arguments

	# Define custom event names for this module.  A custom event is triggered
	# whenever result data becomes available after making an API request.
	eventList = [
		'od.clientaccess'
		'od.libraryinfo'
		'od.metadata'
		'od.availability'

		'od.patronaccess'
		'od.patroninfo'
		'od.holds'
		'od.checkouts'
		'od.interests'
		'od.action'

		'od.hold.update'
		'od.hold.delete'
		'od.checkout.update'
		'od.checkout.delete'

		'od.prefs'
		'od.login'
		'od.logout'
		'od.error'
	]
	eventObject = $({}).on eventList.join(' '), (e, x, y...) ->
		# Uncomment for debugging on console
		#log e.namespace, x, y

	# On page load, we unserialize the text string found in local storage into
	# an object, or if there is no string yet, we create the default object.
	# The session object uses a local storage mechanism based on window.name;
	# see
	# http://stackoverflow.com/questions/2035075/using-window-name-as-a-local-data-cache-in-web-browsers
	# for pros and cons and alternatives.
	session = new Session window.name, Boolean C('eg_loggedin') or window.IAMXUL

	# On window unload, we serialize it into local storage so that it survives
	# page reloads.
	$(window).on 'unload', -> window.name = session.store()

	# Customize the plain jQuery ajax to post a request for an access token
	_api = (url, data) ->

		$.ajax $.extend {},
			# The Basic Authorization string is always added to the HTTP header.
			headers: Authorization: "Basic #{config.credentials}"
			url: url
			type: 'POST'
			# We expect data to be always given; the ajax method will convert
			# it to a query string.
			data: data

	# Convert a serialized array into a serialized object
	serializeObject = (a) ->
		o = {}
		$.each a, ->
			v = @value or ''
			if (n = o[@name]) isnt undefined
				o[@name] = [n] unless n.push
				o[@name].push v
			else
				o[@name] = v
		return o

	# TODO unused
	$.fn.extend

		# Convert this serialized array to a serialized object
		_serializeObject: -> serializeObject @serializeArray()

		# Serialize this to a json string, an object, an array, a query string, or just return itself
		_serializeX: (X) ->
			switch X
				when 'j' then json.stringify @_serializeX 'o'
				when 'k' then json.stringify @_serializeX 'a'
				when 'p' then $.param @_serializeX 'a'
				when 's' then @serialize()
				when 'o' then serializeObject @_serializeX 'a'
				when 'a' then @serializeArray()
				else @


	# We define the public interface of the module
	# TODO wrap od in jquery so that we can use it to trigger events and bind event handlers
	od =

		# Povides the anchor object for implementing a publish/subscribe
		# mechanism for this module.
		$: eventObject.on

			# Notification that there are possible changes of values from
			# preferences page that should be updated in the session cache
			'od.prefs': (ev, x) -> session.prefs.update x

			# Expire patron access token if user is no longer logged into EG
			'od.logout': (ev, x) ->
				if x is 'eg'
					session = new Session() if session.token.is_patron_access()

		log: log

		# Map format id to format name using current session object
		labels: (id) -> session.labels[id] or id

		# Customize the plain jQuery ajax method to handle a GET or POST method
		# for the Overdrive api.
		api: (url, method, data, beforeSend) ->

			#  Do some pre-processing of data before it is sent to server
			if method is 'post'

				# Convert numberOfDays value from an ISO 8601 date string to
				# number of days relative to now.  There are two subtleties
				# regarding rounding errors: First, we use only use now of
				# resolution to days to avoid a local round-down from 1 to 0.
				# Second, we need to add one to avoid a round-down at the OD
				# server.
				for v in data.fields when v.name is 'numberOfDays'
					v.value = 1 + M(v.value).diff M().toArray()[0..2], 'days'

			$.ajax $.extend {},
				# The current Authorization string is always added to the HTTP header.
				headers: Authorization: "#{session.token.token_type} #{session.token.access_token}"
				url: url
				# Will default to 'get' if no method string is supplied
				type: method
				# A given data object is expected to be in JSON format
				contentType: 'application/json; charset=utf-8'
				data: json.stringify data
				beforeSend: beforeSend

			.done ->

				# For a post method, we get a data object in reply.  We publish
				# the object using an event named after the data type, eg,
				# 'hold', 'checkout'.  We can't easily recognize the data type
				# by looking at the data, so we have to pattern match on the
				# API URL.
				if method is 'post'
					if /\/holds|\/suspension/.test url
						x = new D.Holds holds: [ arguments[0] ]
						od.$.triggerHandler 'od.hold.update', x
					if /\/checkouts/.test url
						x = new D.Checkouts checkouts: [ arguments[0] ]
						od.$.triggerHandler 'od.checkout.update', x

				# For a delete method, we do not get a data object in reply,
				# thus we pattern match for the specific ID, and trigger an
				# event with the ID.
				if method is 'delete'
					if id = url.match /\/holds\/(.+)\/suspension$/
						return # no relevant event
					if id = url.match /\/holds\/(.+)$/
						od.$.triggerHandler 'od.hold.delete', id[1]
					if id = url.match /\/checkouts\/(.+)$/
						od.$.triggerHandler 'od.checkout.delete', id[1]

			.fail ->
				od.$.triggerHandler 'od.error', [url, arguments[0]]
				#$('<div>')._notify arguments[1].statusText, arguments[0].responseText

		# Get a library access token so that we can use the Discovery API.
		# The token is cached and also published to other modules.
		apiDiscAccess: ->

			ok = (x) ->
				session.token.update x
				od.$.triggerHandler 'od.clientaccess', x
				return x

			_api session.links.token.href, grant_type: 'client_credentials'

			.then ok, logError

		# Use the Library Account API to get library account information,
		# primarily the product link and the available formats.  Since we
		# schedule this call on every page load, it will also tell us if
		# our access token has expired or not.
		#
		# If a retry is needed, we have to decide whether to get a library
		# access token or a patron access token.  However, getting the latter
		# will, in the general case, require user credentials, which means we
		# need to store the password in the browser across sessions.  An
		# alternative is to force a logout, so that the user needs to manually
		# relogin. In effect, we would only proceed with a retry to get a
		# library access token, but if the user has logged in, we would not.
		#
		apiLibraryInfo: ->

			get = -> od.api session.links.libraries.href

			ok = (x) ->
				session.links.update x
				session.labels.update x
				od.$.triggerHandler 'od.libraryinfo', x
				return x

			retry = (jqXHR) ->

				# Retry if we got a 401 error code
				if jqXHR.status is 401

					if session.token.is_patron_access()
						# Current OD patron access token may have expired
						od.$.triggerHandler 'od.logout', 'od'

					else
						# Renew our access token and retry the get operation
						od.apiDiscAccess()
						.then get, logError
						.then ok

			get().then ok, retry

		# We define a two-phase sequence to get a patron access token, for example,
		# login(credentials); do_something_involving_page_reload(); login();
		# where credentials is an object containing username and password
		# properties from the login form.
		#
		# Logging into Evergreen can proceed using either barcode or user name,
		# but logging into Overdrive is only a natural act using barcode. In
		# order to ensure that logging into OD with a username can proceed, we
		# presume that EG has been logged into and, as a prelude, we get the
		# Preferences page of the user so that we can scrape out the barcode
		# value for logging into OD.
		#
		# The login sequence is associated with a cache that remembers the
		# login response ('parameters') between login sessions. The epilogue to
		# the login sequence is to use the Patron Information API to get URL
		# links and templates that will allow the user to make further use of
		# the Circulation API.
		login: (credentials) ->

			# Temporarily store the username and password from the login form
			# into the session cache, and invalidate the session token so that
			# the final part of login sequence can complete.
			if credentials
				session.creds.update credentials
				session.token.update()
				od.$.triggerHandler 'od.login'
				return

			# Return a promise to a resolved deferredment if session token is still valid
			# TODO is true if in staff client but shouldn't be
			if session.token.is_patron_access()
				return $.Deferred().resolve().promise()

			# Request OD service for a patron access token using credentials
			# pulled from the patron's preferences page
			login = (prefs) ->

				# Define a function to cut the value corresponding to a label
				# from prefs
				x = (label) ->
					r = new RegExp "#{label}<\\/td>\\s+<td.+>(.*?)<\\/td>", 'i'
					prefs.match(r)?[1] or ''

				# Retrieve values from preferences page and save them in the
				# session cache for later reference
				session.prefs.update
					barcode:       x 'barcode'
					email_address: x 'email address'
					home_library:  x 'home library'

				# Use barcode as username or the username that was stored in
				# session cache (in the hope that is a barcode) or give up with
				# a null string
				un = session.prefs.barcode or session.creds.un()

				# Use the password that was stored in session cache or a dummy value
				pw = session.creds.pw config.password_required

				# Remove the stored credentials from cache as soon as they are
				# no longer needed
				session.creds.update()

				# Determine the Open Auth scope by mapping the long name of EG
				# home library to OD authorization name
				scope = "websiteid:#{config.websiteID} authorizationname:#{config.authorizationname session.prefs.home_library}"

				# Try to get a patron access token from OD server
				_api session.links.patrontoken.href,
					grant_type: 'password'
					username: un
					password: pw
					password_required: config.password_required
					scope: scope

			# Complete login sequence if the session cache is invalid
			ok = (x) ->
				session.token.update x
				od.$.triggerHandler 'od.patronaccess', x
				return x

			# Get patron preferences page
			$.get '/eg/opac/myopac/prefs'
			# Get the access token using credentials from preferences
			.then login
			# Update the session cache with access token
			.then ok
			# Update the session cache with session links
			.then od.apiPatronInfo
			.fail log

		# TODO not used; EG catalogue is used instead
		apiSearch: (x) ->
			return unless x
			od.api session.links.products.href, get, x

		apiMetadata: (x) ->
			return unless x.id

			od.api "#{session.links.products.href}/#{x.id}/metadata"

			.then (y) ->
				y = new D.Metadata y
				od.$.triggerHandler 'od.metadata', y
				y

			.fail -> od.$.triggerHandler 'od.metadata', x

		apiAvailability: (x) ->
			return unless x.id

			url =
				if (alink = session.links.availability?.href)
					alink.replace '{crId}', x.id # Use this link if logged in
				else
					"#{session.links.products.href}/#{x.id}/availability"

			od.api url

			.then (y) ->
				y = new D.Availability y, session.prefs.email_address
				od.$.triggerHandler 'od.availability', y
				return y

			.fail -> od.$.triggerHandler 'od.availability', x

		apiPatronInfo: ->

			ok = (x) ->
				session.links.update x
				od.$.triggerHandler 'od.patroninfo', x
				return x

			od.api session.links.patrons.href
			.then ok, logError

		# Get a specific hold or all holds
		apiHoldsGet: (x) ->
			return unless session.token.is_patron_access()

			od.api "#{session.links.holds.href}#{if x?.productID then x.productID else ''}"

			.then (y) ->
				y = new D.Holds y
				od.$.triggerHandler 'od.holds', y
				return y

		# Get a specific checkout or all checkouts
		apiCheckoutsGet: (x) ->
			return unless session.token.is_patron_access()

			od.api "#{session.links.checkouts.href}#{if x?.reserveID then x.reserveID else ''}"

			.then (y) ->
				y = new D.Checkouts y
				od.$.triggerHandler 'od.checkouts', y
				return y

		# Consolidate the holds and checkouts lists into an object that
		# represents the 'interests' of the patron
		apiInterestsGet: ->
			$.when(
				od.apiHoldsGet()
				od.apiCheckoutsGet()
			)
			.then (h, c) ->
				y = new D.Interests h, c
				od.$.triggerHandler 'od.interests', y
				return y

	return od
