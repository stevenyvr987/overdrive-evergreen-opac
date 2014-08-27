define [
	'jquery'
	'lodash'
	'json'
	'cookies'
	'moment'
	'od_config'
], ($, _, json, C, M, config) ->

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
		'od.libraryaccount'
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
	eventObject = $({}).on eventList.join(' '), (e, x, y...) -> log e.namespace, x, y

	# We require the service of a session object to store essentials bits of
	# information during a login session and between page reloads.  Here, we
	# define the default version of the session, which will be used if no
	# session is active.
	default_session =

		prefs: {}

		credentials: {}

		# An essential role of the session object is to store the response
		# parameters that are provided as a result of authenticating the client
		# or the patron.  Two components, the token type and the token, are
		# computed into an Authorization header so that they can be easily
		# submitted to an ajax call.
		token: {}
			#parameters: ''
			#headers: Authorization: ''

		# Another role is to store the endpoints of the various APIs.  These
		# include the endpoints for authenticating the client or the patron and
		# the endpoints for getting library or patron information.  Upon
		# authentication, other endpoints are dynamically accumulated within
		# the session object.
		links:
			token: href:              '//oauth.overdrive.com/token'
			libraries: href:            "//api.overdrive.com/v1/libraries/#{config.accountID}"
			patrontoken: href: '//oauth-patron.overdrive.com/patrontoken'
			patrons: href:       '//patron.api.overdrive.com/v1/patrons/me'
			holds: href: ''
			checkouts: href: ''
			products: ''
			advantageAccounts: ''
			search: ''
			availability: ''

		# Another role is to preserve the mapping between format id and format
		# name that will be provided by the Library Account API.
		labels: {}

	# The session object uses a local storage mechanism based on window.name;
	# see
	# http://stackoverflow.com/questions/2035075/using-window-name-as-a-local-data-cache-in-web-browsers
	# for pros and cons and alternatives.
	#
	# On page load, we unserialize the text string found in local storage into
	# an object, or if there is no string yet, we create the default object.
	session =
		try
			json.parse window.name
		catch
			default_session

	# On window unload, we timestamp the current session object and serialize it
	# into local storage so that it survives page reloads.
	$(window).on 'unload', ->
		session.now = M().toISOString()
		window.name = json.stringify session

	# Use a cheap, nasty way to enforce a sanity constraint: session link templates should have empty
	# values unless the current session is logged in.
	$.extend session.links, { search: '', availability: '' } unless Boolean C('eg_loggedin') or window.IAMXUL

	# Return a new object from given an object that has a 'key' property and a
	# 'value' property
	to_object = (from, key, value) ->
		to = {}
		to[x[key]] = x[value] for x in from
		return to

	# Update library or patron account information for the session
	update_session_cache = (x) ->

		# Cache any links
		$.extend session.links, x.links if x.links

		# Cache any linkTemplates; these are sourced only via the Patron Information API
		$.extend session.links, x.linkTemplates if x.linkTemplates

		#$.extend session, x

		# Cache any mapping between format names and format IDs
		$.extend session.labels, to_object x.formats, 'id', 'name' if x.formats

		return x

	# Revert the session cache to its default version
	expire_session_cache = ->
		$.extend session, default_session

	# Define a function to check if the session object contains a patron access
	# token.  It is enough to test if the parameters.scope text string mentions
	# the word 'patron'.
	#is_patron_access_token = -> /patron/i.test session.token.parameters?.scope
	is_patron_access_token = -> /patron/i.test session.token?.scope

	# Calculate a string encompassing the token type and access token of a
	# given response object to an Overdrive login request
	token_header = (x) -> Authorization: "#{x.token_type} #{x.access_token}"

	# Customize the plain jQuery ajax to post a request for an access token
	_api = (url, data) ->

		$.ajax $.extend {},
			# The Basic Authorization string is always added to the HTTP header.
			headers: Authorization: "Basic #{config.credentials}"
			# The URL endpoint is converted to its reverse proxy version,
			# because we are using the Evergreen server as a reverse proxy to
			# the Overdrive server.
			url: proxy url
			type: 'POST'
			# We expect data to be always given; the ajax method will convert
			# it to a query string.
			data: data

	# Replace the host domain of a given URL with a proxy domain.  If the input
	# URL specifies a protocol, it is stripped out so that the output will
	# default to the client's protocol.
	proxy = (x) ->
		return unless x
		y = x
		y = y.replace 'https://', '//'
		y = y.replace 'http://' , '//'
		y = y.replace '//oauth-patron.overdrive.com', '/od/oauth-patron'
		y = y.replace        '//oauth.overdrive.com', '/od/oauth'
		y = y.replace   '//patron.api.overdrive.com', '/od/api-patron'
		y = y.replace          '//api.overdrive.com', '/od/api'
		y = y.replace  '//images.contentreserve.com', '/od/images'
		y = y.replace '//fulfill.contentreserve.com', '/od/fulfill'
		#log "proxy #{x} -> #{y}"
		y

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

	# Mutate an ISO 8601 date string into a Moment object.  If the argument is
	# just a date value, then it specifies an absolute date in ISO 8601 format.
	# If the argument is a pair, then it specifies a date relative to now.  For
	# an ISO 8601 date, we correct for what seems to be an error in time zone,
	# Zulu time is really East Coast time.
	momentize = (date, unit) ->
		switch arguments.length
			when 1
				if date then M(date.replace /Z$/, '-0400') else M()
			when 2
				if date then M().add date, unit else M()
			else M()

	# We define the public interface of the module
	# TODO wrap od in jquery so that we can use it to trigger events and bind event handlers
	od =

		# Povides the anchor object for implementing a publish/subscribe
		# mechanism for this module.
		$: eventObject.on

			# Notification that there are possible changes of values from
			# preferences page that should be updated in the session cache
			'od.prefs': (ev, x) -> $.extend session.prefs, x

			# Expire patron access token if user is no longer logged into EG
			'od.logout': (ev, x) ->
				if x is 'eg'
					expire_session_cache if is_patron_access_token()

		log: log

		# It's necessary to expose the session cache to other modules because
		# they may need to access certain stored values, in particular, the
		# place hold page needs to get access to the email address
		session: session

		proxy: proxy

		# Map format id to format name using current session object
		labels: (id) -> session.labels[id] or id

		# Customize the plain jQuery ajax method to handle a GET or POST method
		# for the Overdrive api.
		api: (url, method, data) ->

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
				headers: session.token.headers
				# The URL endpoint is converted to its reverse proxy version, because
				# we are using the Evergreen server as a reverse proxy to the Overdrive
				# server.
				url: proxy url
				# Will default to 'get' if no method string is supplied
				type: method
				# A given data object is expected to be in JSON format
				contentType: 'application/json; charset=utf-8'
				data: json.stringify data

			.done ->

				# For a post method, we get a data object in reply.  We publish
				# the object using an event named after the data type, eg,
				# 'hold', 'checkout'.  We can't easily recognize the data type
				# by looking at the data, so we have to pattern match on the
				# API URL.
				if method is 'post'
					if /\/holds|\/suspension/.test url
						x = arguments[0]
						x.holdPlacedDate = momentize x.holdPlacedDate
						x.holdExpires = momentize x.holdExpires
						if x.holdSuspension
							x.holdSuspension.numberOfDays = momentize x.holdSuspension.numberOfDays, 'days'
						od.$.triggerHandler 'od.hold.update', x
					if /\/checkouts/.test url
						x = arguments[0]
						x.expires = momentize x.expires
						od.$.triggerHandler 'od.checkout.update', x

				# For a delete method, we do not get a data object in reply,
				# thus we pattern match for the specific ID and trigger an
				# event with the ID.
				if method is 'delete'
					if id = url.match /\/holds\/(.+)\/suspension$/
						return # no relevant event
					if id = url.match /\/holds\/(.+)$/
						od.$.triggerHandler 'od.hold.delete', reserveId: id[1]
					if id = url.match /\/checkouts\/(.+)$/
						od.$.triggerHandler 'od.checkout.delete', reserveId: id[2]

			.fail ->
				od.$.triggerHandler 'od.error', [url, arguments[0]]
				#$('<div>')._notify arguments[1].statusText, arguments[0].responseText

		# Get a library access token so that we can use the Discovery API
		apiDiscAccess: ->

			ok = (x) ->
				# Cache the server's response object as a general reference point
				#session.token.parameters = x
				session.token = x
				# Cache the access token so that it can be used in future api calls
				session.token.headers = token_header x
				od.$.triggerHandler 'od.clientaccess', x

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
		apiAccount: ->

			get = -> od.api session.links.libraries.href

			ok = (x) ->
				update_session_cache x
				od.$.triggerHandler 'od.libraryaccount', x
				return

			retry = (jqXHR) ->

				# Retry if we got a 401 error code
				if jqXHR.status is 401

					if is_patron_access_token()
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
			# into the session cache, and invalidate the session cache so that
			# the final part of login sequence can complete.
			if credentials
				$.extend session.credentials, credentials
				#delete session.token.parameters
				session.token = {}
				od.$.triggerHandler 'od.login'
				return

			# Return a promise to a resolved deferredment if session cache is still valid
			# TODO is true if in staff client but shouldn't be
			#if session.token.parameters
			if is_patron_access_token()
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
				$.extend( session.prefs,
					barcode:       x 'barcode'
					email_address: x 'email address'
					home_library:  x 'home library'
				)

				# Use barcode as username or the username that was stored in
				# session cache (in the hope that is a barcode) or give up with
				# a null string
				un = session.prefs.barcode or session.credentials?.username or ''

				# Use the password that was stored in session cache or a dummy value
				pw = if config.password_required is 'false' then 'xxxx' else session.credentials?.password or 'xxxx'

				# Remove the stored credentials from cache as soon as they are
				# no longer needed
				session.credentials = {}

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
				#session.token.parameters = x
				session.token = x
				session.token.headers = token_header x
				od.$.triggerHandler 'od.patronaccess', x

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

		# TODO we can probably get away with using one normalization routine
		# instead of using one for each type of data object, because they don't
		# share property names.

		apiMetadata: (x) ->
			return unless x.id
			od.api "#{session.links.products.href}/#{x.id}/metadata"

			.then (y) ->
				# Convert ID to upper case to match same case found in EG catalogue
				y.id = y.id.toUpperCase()
				# Provide a simplified notion of author: first name in creators
				# list having a role of author
				y.author = (v.name for v in y.creators when v.role is 'Author')[0] or ''
				# Publish the metadata object
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

			# Post-process the result, eg, fill in empty properties
			.then (y) ->
				# Normalize the result by adding zero values
				y.copiesOwned     = 0 unless y.copiesOwned
				y.copiesAvailable = 0 unless y.copiesAvailable
				y.numberOfHolds   = 0 unless y.numberOfHolds

				if y.actions?.hold
					# The reserve ID is empty in the actions.hold.fields; we have to fill it ourselves.
					_.where(y.actions.hold.fields, name: 'reserveId')[0].value = y.id
					# We jam the email address from the prefs page into the fields object from the server
					# so that the new form will display it.
					if email_address = od.session.prefs.email_address
						_.where(y.actions.hold.fields, name: 'emailAddress')[0].value = email_address

				od.$.triggerHandler 'od.availability', y
				arguments

			.fail -> od.$.triggerHandler 'od.availability', x

		apiPatronInfo: ->
			ok = (x) ->
				update_session_cache x
				od.$.triggerHandler 'od.patroninfo', x
				return

			od.api session.links.patrons.href
			.then ok, logError

		apiHoldsGet: (x) ->
			return unless is_patron_access_token()

			od.api "#{session.links.holds.href}#{if x?.productID then x.productID else ''}"

			# Post-process the result, eg, fill in empty properties, sort list,
			# remove redundant actions or add missing actions
			.then (y) ->

				# Normalize the result by adding an empty holds list
				xs = y.holds or []

				# For each hold, convert any ISO 8601 date strings into a
				# Moment object (at the local time zone)
				for x in xs
					x.holdPlacedDate = momentize x.holdPlacedDate
					x.holdExpires = momentize x.holdExpires
					if x.holdSuspension
						x.holdSuspension.numberOfDays = momentize x.holdSuspension.numberOfDays, 'days'

				# Count the number of holds that can be checked out now
				y.ready = _.countBy xs, (x) -> if x.actions.checkout then 'forCheckout' else 'other'
				y.ready.forCheckout = 0 unless y.ready.forCheckout

				# Delete action to release a suspension if a hold is not
				# suspended, because such actions are redundant
				delete x.actions.releaseSuspension for x in xs when not x.holdSuspension

				# Sort the holds list by position and placed date
				# and sort ready holds first
				#y.holds = _.sortBy xs, ['holdListPosition', 'holdPlacedDate']
				y.holds = _(xs)
					.sortBy ['holdListPosition', 'holdPlacedDate']
					.sortBy (x) -> x.actions.checkout
					.value()

				od.$.triggerHandler 'od.holds', y
				arguments

		apiCheckoutsGet: (x) ->
			return unless is_patron_access_token()

			od.api "#{session.links.checkouts.href}#{if x?.reserveID then x.reserveID else ''}"

			# Post-process the result, eg, fill in empty properties, sort list,
			# remove redundant actions or add missing actions
			.then (y) ->

				# Normalize the result by adding an empty checkouts list
				xs = y.checkouts or []

				# Convert any ISO 8601 date strings into a Moment object (at
				# the local time zone)
				for x in xs
					x.expires = momentize x.expires

				# Sort the checkout list by expiration date
				y.checkouts = _.sortBy xs, 'expires'

				od.$.triggerHandler 'od.checkouts', y
				arguments

		# Get a list of user's 'interests', ie, holds and checkouts
		apiInterestsGet: ->
			$.when(
				od.apiHoldsGet()
				od.apiCheckoutsGet()
			)

			# Consolidate the holds and checkouts information into an object
			# that represents the 'interests' of the patron
			.then (h, c) ->

				# A useful condition to handle if the API calls could not
				# be fulfilled because they are not within the scope of the
				# current access token 
				# TODO possibly redundant or unnecessary
				###
				unless h and c
					page {}, {}
					return
				###

				h = h[0]
				c = c[0]

				interests =
					nHolds: h.totalItems
					nHoldsReady: h.ready.forCheckout
					nCheckouts: c.totalItems
					nCheckoutsReady: c.totalCheckouts
					ofHolds: h.holds
					ofCheckouts: c.checkouts
					# The following property is a map from product ID to a hold or
					# a checkout object, eg, interests.byID(124)
					byID: do (hs = h.holds, cs = c.checkouts) ->
						byID = {}
						for v, n in hs
							v.type = 'hold'
							byID[v.reserveId] = v
						for v, n in cs
							v.type = 'checkout'
							byID[v.reserveId] = v
						return byID

				# Publish patron's interests to all areas of the screen
				od.$.triggerHandler 'od.interests', interests
				return interests

	return od
