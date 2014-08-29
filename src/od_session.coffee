# We require the service of a session object to store essentials bits of
# information during a login session and between page reloads.  Here, we
# define a Session class implementing the service.

define [
	'json'
	'lodash'
	'od_config'
], (
	json
	_
	config
) ->

	# A base class defining utilitarian methods
	class U
		update: (x) ->
			return unless x
			t = @
			t extends x
			return
		store: ->
			json.stringify @, ( (n, v) -> if n is 'prototype' then undefined else v ), '  '
		retrieve: (x) ->
			x = if _.isString x
				try
					json.parse x
				catch
					undefined

	class Prefs extends U
		@default:
			barcode: ''
			email_address: ''
			home_library: ''
		constructor: (x) -> @update x
		update: (x) -> super x or Prefs.default

	class Creds extends U
		@default:
			username: ''
			password: 'xxxx'
		constructor: (x) -> @update x
		update: (x) -> super x or Creds.default

		# Calculate the effective username: either a barcode or a username (in the
		# hope that is a barcode) stored in session cache, or default to a null
		# string
		un: -> @barcode or @username

		# Calculate the effective password: either a password stored in session
		# cache or a dummy value
		pw: (required) -> if required then @password else 'xxxx'

	# An essential role of the session object is to store the properties that
	# are provided as a result of authenticating the client or the patron.
	class Token extends U
		@default:
			access_token: undefined
			expires_in: undefined
			scope: undefined
			token_type: undefined

		constructor: (x) -> @update x
		update: (x) -> super x or Token.default
		# Is there a patron access token?  It is enough to test if the
		# parameters.scope text string mentions the word 'patron'.
		is_patron_access: -> /patron/i.test @scope

	# Store the endpoints of the various APIs.  These include the endpoints for
	# authenticating the client or the patron and the endpoints for getting
	# library or patron information.  Upon authentication, other endpoints are
	# dynamically accumulated within the object.
	class Links extends U
		@default:
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
		constructor: (x, logged_in) ->
			@update x
			@calibrate logged_in if x
			return
		update: (x) ->
			if x is undefined
				super Links.default
			else
				super x.links if x.links
				super x.linkTemplates if x.linkTemplates
			return

		# Link templates should have empty values unless the current session is
		# logged in.
		calibrate: (logged_in) ->
			@search = @availability = '' unless logged_in
			return @

	# Preserve the mapping between format id and format name that will be
	# provided by the Library Account API.
	class Labels extends U
		constructor: (x) -> @update x
		update: (x) -> super @to_object x.formats, 'id', 'name' if x?.formats
		# Return a new object from given an object that has a 'key' property and a
		# 'value' property
		to_object: (from, key, value) ->
			to = {}
			if from?.length > 0
				to[x[key]] = x[value] for x in from
			return to

	# Define a session object as a collection of sub-objects of the types just
	# defined. Property values of any sub-object can be given in the argument.
	# The argument can be a JSON string or an object.  If there are no property
	# values given for a sub-object, intrinsic values will be used.
	class Session extends U
		constructor: (x, logged_in) ->
			x = @retrieve x
			@prefs = new Prefs  x?.prefs
			@creds = new Creds  x?.creds
			@token = new Token  x?.token
			@links = new Links  x, logged_in
			@labels= new Labels x
			return

	return Session
