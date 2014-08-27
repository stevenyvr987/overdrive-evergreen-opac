# TODO memory leaks
#
# TODO Author/Title links could specify ebook filter
#
# TODO If logged in, could bypass place hold page and use action dialogue directly
#
# TODO Simple, cheap two-way data binding:
# We could publish a partial request object as an abstract way of making
# an API request, ie, od.$.triggerHandler 'od.metadata', id: id
# Subscribe to same event to receive reply object, ie,
# od.$.on 'od.metadata', (ev, reply) -> # do something with reply

require.config

	paths:
		jquery:      'https://ajax.googleapis.com/ajax/libs/jquery/2.1.1/jquery.min'
		'jquery-ui': 'https://ajax.googleapis.com/ajax/libs/jqueryui/1.11.1/jquery-ui.min'
		lodash:      'https://cdnjs.cloudflare.com/ajax/libs/lodash.js/2.4.1/lodash.min'
		moment:      'https://cdnjs.cloudflare.com/ajax/libs/moment.js/2.5.1/moment.min'
		cookies:     'https://cdnjs.cloudflare.com/ajax/libs/Cookies.js/0.3.1/cookies.min'
		json:        'https://cdnjs.cloudflare.com/ajax/libs/json3/3.3.0/json3.min'

	waitSeconds: 120

require [
	'jquery'
	'lodash'
	'cookies'
	'od_api'
	'od_pages_opac'
	'od_pages_myopac'
	'od_action'
], ($, _, C, od) ->

	# Indicate the logged in status; the value is determined within document
	# ready handler.
	logged_in = false

	# Various debugging functions; not used in production
	log_page = -> console.log window.location.pathname
	notify = (what) -> console.log "#{what} is in progress"
	failed = (what) -> console.log "#{what} failed"
	reload_page = -> window.location.reload true
	replace_page = (href) -> window.location.replace href

	# Query a search string of the current page for the value or existence of a
	# property
	search_params = (p) ->
		# Convert for example, '?a=1&b=2' to { a:1, b:2 }, 
		o =
			if xs = (decodeURI window.location.search)?.split('?')?[1]?.split('&')
				_.zipObject( x.split('=') for x in xs )
			else
				{}
		# Return either the value of a specific property, whether the property
		# exists, or the whole object
		if arguments.length is 1 then o[p] or o.hasOwnProperty p else o


	# Return an abbreviation of the pathname of the current page,
	# eg, if window.location.pathname equals 'eg/opac/record' or
	# 'eg/opac/record/123', then return 'record', otherwise return ''
	page_name = ->
		xs = window.location.pathname.match /eg\/opac\/(.+)/
		if xs then xs[1].replace /\/\d+/, '' else ''

	# Make a map from an item ID to a status indicating whether it is on the
	# holds list or the checkout list
	# eg, var status = ids(holds, checkouts)[id]
	item_status = (holds, checkouts) ->
		ids = {}
		ids[v.reserveId] = 'hold' for v, n in holds
		ids[v.reserveId] = 'checkout' for v, n in checkouts
		return ids

	# Routing table: map an URL pattern to a handler that will perform actions
	# or modify areas on the screen.
	routes =

		# Scan through property names and execute the function value if the
		# name pattern matches against the window.location.pathname, eg,
		# routes.handle(). handle() does not try to execute itself.  Returns a
		# list of results for each handler that was executed. A result is
		# undefined if no subscriptions to an OD service was needed.
		handle: (p = window.location.pathname) ->
			for n, v of routes when n isnt 'handle'
				v() if (new RegExp n).test p

		'eg\/opac': ->

			# Add a new dashboard to show total counts of e-items.
			# Start the dashboard w/ zero counts.
			$dash = $('#dash_wrapper')._dashboard()

			od.$.on

				# Set the dashboard counts to summarize the patron's account
				'od.interests': (ev, x) -> $dash._dashboard
					ncheckouts:  x.nCheckouts
					nholds:      x.nHolds
					nholdsready: x.nHoldsReady

				# Decrement the dashboard counts because an item has been
				# removed from the holds or checkout list
				'od.hold.delete': -> $dash._dashboard nholds: -1
				'od.checkout.delete': -> $dash._dashboard ncheckouts: -1

				# Log out of EG if we are logged in and if an OD patron access
				# token seems to have expired
				'od.logout': (ev, x) ->
					if x is 'od'
						$('#logout_link').trigger 'click' if logged_in

		'opac\/myopac': ( this_page = page_name() ) ->

			# Add a new tab for e-items to the current page if it is showing a
			# system of tabs
			$('#acct_holds_tabs, #acct_checked_tabs')._etabs this_page, search_params 'e_items'
			# Relabel history tabs if they are showing on current page
			$('#tab_holds_history, #tab_circs_history')._tab_history()
			return

		'opac\/home': ->

			# Signal that EG may have logged out
			od.$.triggerHandler 'od.logout', 'eg' unless logged_in

		'opac\/login': ->

			# On submitting the login form, we initiate the login sequence with the
			# username/password from the login form
			$('form', '#login-form-box').one 'submit', ->
				od.login
					username: $('[name=username]').val()
					password: $('[name=password]').val()


		# TODO In order to perform OD login after EG login, we could
		# automatically get the prefs page and scrape the barcode value,
		# but in the general case, we would also need the password value
		# that was previously submitted on the login page.

		# We could scrape the barcode value from the prefs page by having it
		# being parsed into DOM within an iframe (using an inscrutable sequence
		# of DOM traversal).  Unfortunately, it will reload script tags and
		# make XHR calls unnecessarily.
		#
		# The alternative is to GET the prefs page and parse the HTML string
		# directly for the barcode value, but admittedly, we need to use an
		# inscrutable regex pattern.

		# On the myopac account summary area, add links to hold list and
		# checkout list of e-items
		'myopac\/main': ( $table = $('.acct_sum_table') ) ->
			return unless $table.length

			totals = $table._account_summary()
			
			od.$.on 'od.interests', (ev, x) ->

				$table._account_summary
					ncheckouts:  totals[0]
					nholds:	     totals[1]
					nready:	     totals[2]
					n_checkouts: x.nCheckouts
					n_holds:     x.nHolds
					n_ready:     x.nHoldsReady

		# Each time the patron's preferences page is shown, publish values that
		# might have changed because the patron has edited them.  Example
		# scenario: patron changes email address on the prefs page and then
		# places hold, expecting the place hold form to default to the newer
		# address.
		'myopac\/prefs': ->
			$tr = $('#myopac_summary_tbody > tr')
			em = $tr.eq(6).find('td').eq(1).text()
			bc = $tr.eq(7).find('td').eq(1).text()
			hl = $tr.eq(8).find('td').eq(1).text()
			od.$.triggerHandler 'od.prefs', email_address:em, barcode:bc, home_library:hl

		'opac\/results': (interested = {}) ->

			# List of hrefs which correspond to Overdrive e-items
			# TODO this list is duplicated in module od_pages_opac
			hrefs = [
				'a[href*="downloads.bclibrary.ca"]' # Used in OPAC
				'a[href*="elm.lib.overdrive.com"]' # Used in XUL staff client
			]

			# Prepare each row of the results table which has an embedded
			# Overdrive product ID.  A list of Overdrive product IDs is
			# returned, which can be used to find each row directly.
			ids = $(hrefs.join ',').closest('.result_table_row')._results()
			return if ids?.length is 0

			od.$.on

				# When patron holds and checkouts become available...
				'od.interests': (ev, x) ->

					# Initiate request for each Overdrive product ID
					for id in ids
						od.apiMetadata id: id
						od.apiAvailability id: id

					# Cache the relationship between product IDs and patron
					# holds and checkouts, ie, has the patron placed a hold on
					# an ID or checked out an ID?
					interested = x.byID

				# Fill in format values when they become available
				'od.metadata': (ev, x) -> $("##{x.id}")._results_meta x

				# Fill in availability values when they become available
				'od.availability': (ev, x) ->
					$("##{x.id}")
						._results_avail x
						._replace_place_hold_link x, interested[x.id]?.type

		'opac\/record': (interested = {}) ->

			# Add an empty container of format and availability values
			return unless id = $('div.rdetail_uris')._record()

			od.$.on

				# When patron holds and checkouts become available...
				'od.interests': (ev, x) ->

					# Initiate request for metadata and availability values when
					od.apiMetadata id: id
					od.apiAvailability id: id

					# Has the user placed a hold on an ID or checked out an ID?
					interested = x.byID

				# Fill in format values when they become available
				'od.metadata': (ev, x) -> $("##{x.id}")._record_meta x

				# Fill in availability values when they become available
				'od.availability': (ev, x) ->
					$("##{x.id}")._record_avail x
					$('#rdetail_actions_div')._replace_place_hold_link x, interested[x.id]?.type

		# For the case where the patron is trying to place a hold if not logged
		# in, there is a loophole in the Availability API; if using a patron
		# access token and patron already has a hold on it, avail.actions.hold
		# will still be present, falsely indicating that patron may place a
		# hold, which will lead to a server error. The same situation will
		# occur if patron has already checked out.  It seems the OD server does
		# not check the status of the item wrt the patron before generating the
		# server response.
		#
		# To fix the problem, we will check if avail.id is already held or
		# checked out, and if so, then go back history two pages so that
		# original result list or record page is shown, with the proper action
		# link generated when the page reloads.

		# Replace the original Place Hold form with a table row to show
		# available actions, either 'Check out' or 'Place hold', depending on
		# whether the item is available or not, respectively.
		#
		# The following page handler does not replace the place_hold page, but
		# is meant to be called by the place hold link.
		# If the place_hold page is encountered, the handler will return
		# without doing anything, because no id is passed in.
		'opac\/place_hold': (id, interested = {}) ->
			return unless id

			$('#myopac_holds_div')._replace_title 'Place E-Item on Hold'
			$('#myopac_checked_div')._replace_title 'Check out E-Item'

			$('#holds_main, #checked_main, .warning_box').remove()

			$div = $('<div id="#holds_main">')
				._holds_main() # Add an empty table
				._holdings_row id # Add an empty row
				.appendTo $('#myopac_holds_div, #myopac_checked_div')

			# Fill in metadata values when they become available
			od.$.on

				'od.interests': (ev, x) ->
					od.apiMetadata id: id
					od.apiAvailability id: id
					# Has the user placed a hold on an ID or checked out an ID?
					interested = x.byID

				'od.metadata': (ev, x) ->
					$("##{x.id}")._row_meta x, 'thumbnail', 'title', 'author', 'formats'

				'od.availability': (ev, x) ->
					# Check if this patron has checked out or placed a hold on
					# avail.id and if so, then go back two pages to the result list
					# or record page. The page being skipped over is the login page
					# that comes up because the user needs to log in before being
					# able to see the place hold page.  Thus, the logic is only
					# relevant if the user has not logged in before trying to place
					# a hold.
					if interested[x.id]?.type
						window.history.go -2
					else
						$("##{x.id}")._holdings_row_avail x

		'myopac\/holds': ->

			# If we arrive here with an interested ID value, we are intending
			# to place a hold on an e-item
			if id = search_params 'interested'
				return routes['opac\/place_hold'] id

			# Rewrite the text in the warning box to distinguish physical items from e-items
			unless search_params 'e_items'
				$('.warning_box').text $('.warning_box').text().replace ' holds', ' physical holds'
				return

			return unless ($holds_div = $('#myopac_holds_div')).length

			$holds_div._replace_title 'Current E-Items on Hold'

			$('#holds_main, .warning_box').remove()

			# Replace with an empty table for a list of holds for e-items
			$div = $('<div id="#holds_main">')
				._holds_main()
				.appendTo $holds_div

			# Subscribe to notifications of relevant data objects
			od.$.on

				'od.interests': (ev, x) ->

					# Focus on patron's hold interests, and if the search
					# parameters say so, further focus on holds of items that
					# are ready to be checked out
					holds = x?.ofHolds
					holds = _.filter(holds, (x) -> x.actions.checkout) if search_params 'available'

					# Add an empty list of holds
					ids = $div._holds_rows holds

					# Try to get the metadata and availability values for
					# this hold
					for id in ids
						od.apiMetadata id: id
						od.apiAvailability id: id

				# Add metadata values to a hold
				'od.metadata': (ev, x) -> $("##{x.id}")._row_meta x, 'thumbnail', 'title', 'author', 'formats'
				# Add availability values to a hold
				'od.availability': (ev, x) -> $("##{x.id}")._holds_row_avail x

				'od.hold.update': (ev, x) -> $("##{x.reserveId}")._holds_row x
				'od.hold.delete': (ev, x) -> $("##{x.reserveId}").remove()

		'myopac\/circs': ->

			# If we arrive here with an interested ID value, we are intending
			# to checking out an e-item
			if id = search_params 'interested'
				return routes['opac\/place_hold'] id

			# Rewrite the text in the warning box to distinguish physical items from e-items
			unless search_params 'e_items'
				$('.warning_box').text $('.warning_box').text().replace ' items', ' physical items'
				return
			
			return unless ($checked_div = $('#myopac_checked_div')).length

			$checked_div._replace_title 'Current E-Items Checked Out'

			$('#checked_main, .warning_box').remove()

			# Build an empty table for a list of checkouts of e-items
			$div = $('<div id="#checked_main">')
				._checkouts_main()
				.appendTo $checked_div

			# Subscribe to notifications of relevant data objects
			od.$.on

				'od.interests': (ev, x) ->

					# Fill in checkout list
					ids = $div._checkouts_rows x?.ofCheckouts

					# Try to get metadata values for these checkouts
					od.apiMetadata id: id for id in ids

				# Add metadata values to a checkout
				'od.metadata': (ev, x) -> $("##{x.id}")._row_meta x, 'thumbnail', 'title', 'author'

				'od.checkout.update': (ev, x) -> $("##{x.reserveId}")._row_checkout x
				'od.checkout.delete': (ev, x) -> $("##{x.reserveId}").remove()

	# Begin sequence after the DOM is ready...
	$ ->

		return if window.IAMXUL # Comment out to run inside XUL staff client

		# We are logged into EG if indicated by a cookie or if running
		# inside XUL staff client.
		logged_in = Boolean C('eg_loggedin') or window.IAMXUL

		# Dispatch handlers corresponding to the current location
		# and return immediately if none of them require OD services
		return if _.every routes.handle() , (r) -> r is undefined

		# Try to get library account info
		od.apiAccount()

		# If we are logged in, we 'compute' the patron's interests in product
		# IDs; otherwise, we set patron interests to an empty object.
		.then ->

			# If logged in, ensure that we have a patron access token from OD
			# before getting patron's 'interests'
			if logged_in
				od.login().then od.apiInterestsGet

			# Otherwise, return no interests
			# TODO should do the following in od_api module
			else
				interests = byID: {}
				od.$.triggerHandler 'od.interests', interests
				return interests

		return
	return
