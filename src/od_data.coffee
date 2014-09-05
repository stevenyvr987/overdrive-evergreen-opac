define [
	'lodash'
	'moment'
], (
	_
	M
) ->

	# A base class defining utilitarian methods
	class U
		constructor: (x) ->
			return unless x
			t = @
			t extends x
			return

		# Mutate an ISO 8601 date string into a Moment object.  If the argument is
		# just a date value, then it specifies an absolute date in ISO 8601 format.
		# If the argument is a pair, then it specifies a date relative to now.  For
		# an ISO 8601 date, we correct for what seems to be an error in time zone,
		# Zulu time is really East Coast time.
		momentize: (date, unit) ->
			switch arguments.length
				when 1
					if date then M(date.replace /Z$/, '-0400') else M()
				when 2
					if date then M().add date, unit else M()
				else M()

		# The URL endpoint is converted to its reverse proxy version,
		# because we are using the Evergreen server as a reverse proxy to
		# the Overdrive server.
		proxy: (x) ->
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
		proxies: (x) ->
			(v.href = @proxy l) for n, v of x when l = v.href
			return x


	class Metadata extends U
		constructor: (x) ->
			super x

			# Convert ID to upper case to match same case found in EG catalogue
			@id = @id.toUpperCase()
			# Provide a simplified notion of author: first name in creators
			# list having a role of author
			@author = (v.name for v in @creators when v.role is 'Author')[0] or ''
			# Convert image links to use reverse proxy
			@proxies @images

			return


	class Availability extends U
		constructor: (x, email_address) ->
			super x

			@zero()
			@hold email_address if @actions?.hold
			@proxies @actions if @actions?

			return @

		# Add zero values
		zero: ->
			@copiesOwned     = 0 unless @copiesOwned
			@copiesAvailable = 0 unless @copiesAvailable
			@numberOfHolds   = 0 unless @numberOfHolds
			return @

		hold: (email_address) ->
			# The reserve ID is empty in the actions.hold.fields; we have to fill it ourselves.
			_.where(@actions.hold.fields, name: 'reserveId')[0].value = @id
			# We jam the email address from the prefs page into the fields object from the server
			# so that the new form will display it.
			if email_address
				_.where(@actions.hold.fields, name: 'emailAddress')[0].value = email_address
			return @


	class Holds extends U
		constructor: (x) ->
			super x

			@add()
			.remove()
			.proxy_urls()
			.moments()
			.count()
			.sort()

			return

		# Ensure there is always a holds list, even if it's empty
		add: ->
			@holds = [] if @holds is undefined
			return @

		# Delete action to release a suspension if a hold is not
		# suspended, because such actions are redundant
		remove: ->
			delete x.actions.releaseSuspension for x in @holds when not x.holdSuspension
			return @

		proxy_urls: ->
			(@proxies v.actions) for v, n in @holds
			return @
			
		# For each hold, convert any ISO 8601 date strings into a
		# Moment object (at local time zone)
		moments: ->
			for x in @holds
				x.holdPlacedDate = @momentize x.holdPlacedDate
				x.holdExpires = @momentize x.holdExpires
				if x.holdSuspension
					x.holdSuspension.numberOfDays = @momentize x.holdSuspension.numberOfDays, 'days'
			return @

		# Count the number of holds that can be checked out now
		count: ->
			@ready = _.countBy @holds, (x) -> if x.actions.checkout then 'forCheckout' else 'other'
			@ready.forCheckout = 0 unless @ready.forCheckout
			return @

		# Sort the holds list by position and placed date
		# and sort ready holds first
		sort: ->
			@holds = _(@holds)
				.sortBy ['holdListPosition', 'holdPlacedDate']
				.sortBy (x) -> x.actions.checkout
				.value()
			return @


	class Checkouts extends U
		constructor: (x) ->
			super x

			@add()
			.proxy_urls()
			.moments()
			.sort()

			return

		# Ensure there is always a checkouts list, even if it's empty
		add: ->
			@checkouts = [] if @checkouts is undefined
			return @

		proxy_urls:->
			(@proxies v.actions) for v, n in @checkouts
			return @

		# For each checkout, convert any ISO 8601 date strings into a
		# Moment object (at local time zone)
		moments: ->
			for x in @checkouts
				x.expires = @momentize x.expires
			return @

		# Sort the checkout list by expiration date
		sort: ->
			@checkouts = _.sortBy @checkouts, 'expires'
			return @


	class Interests
		constructor: (h, c) ->
			return {
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
			}
	
	return {
		Metadata:     Metadata
		Availability: Availability
		Holds:        Holds
		Checkouts:    Checkouts
		Interests:    Interests
	}
