# TODO cannot auto-focus on close button of action dialog
# probably because it needs to be done asynchronously using setTimeout
#
define [
	'jquery'
	'lodash'
	'json'
	'od_api'
	'jquery-ui'
], ($, _, json, od) ->

	# Load a CSS file related to our use of the jqueryui dialog widget.
	# We manually load the file in order to avoid modifying any .tt2 files.
	do (url = '//ajax.googleapis.com/ajax/libs/jqueryui/1.11.1/themes/smoothness/jquery-ui.min.css') ->
		link = document.createElement('link')
		link.type = 'text/css'
		link.rel  = 'stylesheet'
		link.href = url
		document.getElementsByTagName('head')[0].appendChild(link)

	# Return an abbreviation of the pathname of the current page,
	# eg, if window.location.pathname equals 'eg/opac/record' or
	# 'eg/opac/record/123', then return 'record', otherwise return ''
	brief_name = ->
		xs = window.location.pathname.match /eg\/opac\/(.+)/
		if xs then xs[1].replace /\/\d+/, '' else ''
	# TODO also defined in od_page_rewrite, but we don't want this module to
	# depend on that module, because it depends on this module.

	# Pluck out a sensible message from the reply to an action request
	responseMessage = (x) -> (json.parse x.responseText).message

	# Customize the dialog widget to guide a user through the intention of
	# making a transaction
	#
	# Usage: $('<div>').dialogAction action: action, scenario: scenario
	#
	$.widget 'ui.dialogAction', $.ui.dialog,
		options:
			draggable: false
			resizable: true
			modal: true
			buttons: [
				{
					text: 'Yes'
					click: (ev) ->
						ev.stopPropagation()
						$(@).dialogAction 'yes_action'
						return
				}
				{
					text: 'No'
					click: (ev) ->
						ev.stopPropagation()
						$(@).dialogAction 'non_action'
						return
				}
			]

		# On create, perform custom positioning, and show custom title and
		# body.  When the dialog finally closes, destroy it.
		_create: ->

			intent = @options._scenario?.intent
			position = @options._action?._of

			# Text of Yes/No buttons in the intent scenario may be overridden
			if intent
				ob = @options.buttons
				ib = intent.buttons
				ob[0].text = ib?[0] or 'Yes'
				ob[1].text = ib?[1] or 'No'

			# Position of dialog box may be overridden
			@options.position = of: position, at: 'top', my: 'top' if position

			@_super()

			# On creation, dialog message may be overidden by the intent scenario
			@set_message 'intent', false if intent

			@_on 'dialogactionclose': -> @_destroy()

		# Depending on the given scenario, the title and body of the dialog
		# screen may be set, and the close button may be shown or hidden.
		set_message: (scenario, close, body, title) ->
			@_close_button close
			# Get the scenario properties
			s = @options._scenario[scenario]
			# The body is a text string specified as an argument or as the
			# scenario's body property, or it defaults to a progress bar.
			@element.empty().append body or s?.body or $('<div>').progressbar value: false
			# The title is a text string specified as an argument or as the
			# scenario's title property, or it defaults to the etitle of the
			# attached action object.
			@option 'title', title or s?.title or @options._action._of._etitle()
			return @

		non_action: ->
			@_on 'dialogactionclose': reroute if reroute = @options._scenario?.intent?.reroute
			@close()
			return @

		# Respond to the Yes button by going ahead with the intended action
		yes_action: ->

			# At this point, dialog buttons are turned off.
			@option 'buttons', []

			# Make an API call
			action = @options._action
			progress = => @set_message 'progress', true
			od.api action.href, action.method, fields: $('form', @element).serializeArray(), progress

			# Re-use the dialog to show notifications with a close button
			.then(
				(x) => @set_message 'done', true
				(x) => @set_message 'fail', true, responseMessage x
			)

			# On done and when the user closes the dialog, reroute the page
			.done =>
				@_on 'dialogactionclose': reroute if reroute = this.options._scenario?.done?.reroute

			return @

		# Show or hide the dialog close button
		_close_button: (close) ->
			@element.parent()
				.find('.ui-dialog-titlebar-close')[if close then 'show' else 'hide']()
				.end()
			.end()


	# Map action names to labels
	# TODO also use this mapping in scenarios
	Labels =
		hold: 'Place hold'
		addSuspension: 'Suspend'
		releaseSuspension: 'Activate'
		removeHold: 'Cancel'
		checkout: 'Check out'
		earlyReturn: 'Return title'
		format: 'Select format'


	# We define custom jQuery extensions to perform the actions defined by the
	# Labels object.  The main role of each of these extensions is to build a
	# scenario object that specifies the layout and behaviour of an instance of
	# the action dialog widget.  The specification is dependent on the content
	# of a given action object and hence the scenario object must be built
	# dynamically.
	#
	# TODO Since all of these extensions end with making an identical call to
	# the dialogAction widget, it would be good to abstract the call to the
	# outside environment, perhaps redefine the extensions as simple functions.
	# eg, fn:: action -> scenario
	#
	# TODO Map action names to re-routed page names.  The rerouting function
	# depends on current page, current action, and current scenario
	#
	$.fn.extend

		# Build a dialog to place a hold
		_hold: (action) ->

			scenario =
				intent:
					body: $('<div>')._action_fields action.fields
					buttons: [ 'Place hold', 'Cancel' ]
					# TODO clicking cancel should return to search results, not
					# to rerouted page
					reroute: -> window.history.back()
				done:
					body: 'Hold was successfully placed. Close this box to be redirected to your holds list.'
					reroute: -> window.location.replace '/eg/opac/myopac/holds?e_items'
				fail: body: 'Hold was not placed. There may have been a network or server problem. Please try again.'

			@dialogAction _scenario: scenario, _action: action

		# Build a dialog to cancel a hold
		_removeHold: (action) ->

			scenario =
				intent: body: 'Are you sure you want to cancel this hold?'
				done: body: 'Hold was successfully cancelled.'
				fail: body: 'Hold was not cancelled. There may have been a network or server problem. Please try again.'

			@dialogAction _scenario: scenario, _action: action

		# Build a dialog to suspend a hold
		_addSuspension: (action) ->

			scenario =
				intent:
					body: $('<div>')._action_fields action.fields
					buttons: [ 'Suspend', 'Cancel' ]
				done: body: 'Hold was successfully suspended'
				fail: body: 'Hold was not suspended. There may have been a network or server problem. Please try again.'

			@dialogAction _scenario: scenario, _action: action

		# Build a dialog to release a suspension
		_releaseSuspension: (action) ->

			scenario =
				intent: body: 'Are you sure you want this hold to activate again?'
				done:
					body: 'Suspension was successfully released. The page will reload to update your account status.'
					reroute: -> window.location.reload true
				fail: body: 'Suspension was not released. There may have been a network or server problem. Please try again.'

			@dialogAction _scenario: scenario, _action: action

		# Build a dialog to checkout a title
		_checkout: (action) ->

			scenario =
				intent:
					body: $('<div>')._action_fields action.fields
					buttons: [ 'Check out', 'Cancel' ]
					reroute: ->
						# if at placehold page, go back; otherwise, stay on same page
						# TODO place_hold no longer relevant
						window.history.back() if brief_name() is 'place_hold'
				done:
					body: 'Title was successfully checked out. Close this page to be redirected to your checkouts list.'
					reroute: -> window.location.replace '/eg/opac/myopac/circs?e_items'
				fail: body: 'Title was not checked out. There may have been a network or server problem. Please try again.'

			@dialogAction _scenario: scenario, _action: action

		# Build a dialog to select a format of a title
		_format: (action) ->

			scenario =
				intent:
					body: $('<div>')._action_fields action.fields
					buttons: [ 'Select format', 'Cancel' ]
				done: body: 'Format was successfully selected.'
				fail: body: 'Format was not selected. There may have been a network or server problem. Please try again.'

			@dialogAction _scenario: scenario, _action: action

		# Build a dialog to return a title early
		_earlyReturn: (action) ->

			scenario =
				intent: body: 'Are you sure you want to return this title before it expires?'
				done: body: 'Title was successfully returned.'
				fail: body: 'Title was not returned. There may have been a network or server problem. Please try again.'

			@dialogAction _scenario: scenario, _action: action

		# Build format buttons given specifications as follows.
		# formats = [ { formatType: type, linkTemplates: { downloadLink: { href: href } } } ]
		# actions = { downloadLink: { href: href, method: get, type: type } }
		#
		# TODO no need to define an action dialog because this is the only example of a get action
		# and we can allow the default behaviour to occur.
		#
		# Do we need a dialogDownload widget?
		# Confirm -> HTTP GET downloadLink.
		# Fail -> Browser navigates to errorURL and shows error status.
		# Done -> Response is a contentLink. HTTP Get contentLink.
			
		_formats: (formats) ->
			return @ unless formats

			tpl = _.template """
			<div>
				<a href="<%= href %>" class="opac-button" style="margin-top: 0px; margin-bottom: 0px"><%= label %></a>
			</div>
			"""

			$buttons = for format in formats
				{
					formatType: n
					linkTemplates:
						downloadLink:
							href: href
							type: type
				} = format

				# Create a button for this action
				$ tpl href: href, label: "Download #{od.labels n}"

			@empty().append $buttons

		# Build action buttons and dialogs given specifications as follows.
		# actions = [ { name: { href: h, method: m, fields: [ { name: n, value: v, options: [...] } ] } ]
		_actions: (actions) ->

			tpl = _.template """
			<div>
				<a href="<%= href %>" class="opac-button <%= action_name %>" style="margin-top: 0px; margin-bottom: 0px"><%= label %></a>
			</div>
			"""

			# Find the related row
			$tr = @closest('tr')

			$buttons = for n, action of actions

				# Extend the action object with context
				$.extend action, _of: $tr, _name: n

				# Create a button for this action
				$ tpl href: action.href, action_name: n, label: Labels?[n] or n

				# On clicking the button, build a new dialog using the extended action object
				.on 'click', action, (ev) ->
					ev.preventDefault()
					$('<div>')['_' + ev.data._name] ev.data
					# TODO apply dialogAction method directly as follows.
					#$('<div>').dialogAction _scenario: Actions.scenario[ev.data._name], _action: ev.data
					return false

			@empty().append $buttons

		# Build a form of input fields out of a list of action fields
		_action_fields: (fields) ->

			$('<form>')
			._action_field_hidden  _.where(fields, name: 'reserveId')[0]
			._action_field_email   _.where(fields, name: 'emailAddress')[0]
			._action_field_radio   _.where(fields, name: 'formatType')[0]
			._action_field_suspend _.where(fields, name: 'suspensionType')[0]
			._action_field_date    _.where(fields, name: 'numberOfDays')[0]

			# Show a date field only if suspensionType of indefinite is selected
			.on 'click', '[name=suspensionType]', (ev) ->
				$input = $('[name=numberOfDays]')
				switch @defaultValue
					when 'limited'    then $input.show()
					when 'indefinite' then $input.hide()

			.on 'submit', (ev) ->
				$input = $('[name=numberOfDays]')

		# Build a date field and initially hide it
		_action_field_date: (field) ->

			return @ unless field

			$input = $ """
			<input type="date" name="#{field.name}" value="#{field.value}" />
			"""
			@append $input.hide()

		# Build a hidden input
		_action_field_hidden: (field) ->

			return @ unless field

			@append """
			<input type="hidden" name="#{field.name}" value="#{field.value}" />
			"""

		# Build an email input
		_action_field_email: (field) ->

			return @ unless field

			$input = $ """
			<div>
				You will be notified by email when a copy becomes available
			</div>
			<div>
				<label>Email address: <input type="email" name="#{field.name}" value="#{field.value}" />
				</label>
			</div>
			"""
			$input.find('input').prop 'required', true unless Boolean field.optional

			@append $input

		# Build a group of radio buttons
		_action_field_radio: (field) ->

			return @ unless field

			# If one of the format types is ebook reader, omit it from the
			# list, because it is not a downloadable type
			_.remove field.options, (f) -> f is 'ebook-overdrive'

			# A hint specific to whether format types are optional or not is added to the form
			hint = switch
				when field.options.length is 1 then """
					<div>Only one #{field.name} is available and it has been selected for you</div>
					"""
				when Boolean field.optional then """
					<div>You may select a #{field.name} at this time</div>
					"""
				else """
					<div>Please select one of the available #{field.name}s</div>
					"""
			inputs = for v in field.options
				$x = $ """
				<div>
					<input type="radio" name="#{field.name}" value="#{v}" />#{od.labels v}
				</div>
				"""
				$y = $x.find 'input'
				$y.prop('required', true) unless Boolean field.optional
				$y.prop('checked', true) unless field.options.length > 1
				$x

			@append hint
			.append inputs

		_action_field_suspend: (field) ->

			return @ unless field

			label =
				indefinite: 'Suspend this hold indefinitely'
				limited: 'Suspend this hold for a limited time'

			inputs = for v in field.options
				$x = $ """
				<div><label>
					<input type="radio" name="#{field.name}" value="#{v}" /> #{label[v]}
				</label></div>
				"""
				$y = $x.find 'input'
				$y.prop('required', true) unless Boolean field.optional
				$y.prop('checked', true) if v is 'indefinite'
				$x

			@append inputs

			# We will delegate the handling of download links to the page's
			# tbody.  The sequence of operation is as follows.  We need to get
			# from a download link to make the download request, receive a
			# content link as a response, and then perform a 'normal' get of
			# the content link.  A complexity is to handle the error responses.
			#
			# TODO The initial get could fail, in which case, the errorpageurl
			# will be used to convey the failure status as a query string. We
			# will redirect the error page to the current page and we recognize
			# the error condition by analysing the query parameters.
			#
			# TODO Another error condition could occur if an Overdrive Read
			# ebook is attempted to be downloaded.  Here, the odreadauthurl
			# will be used as a redirect location. We will also redirect to the
			# current page and hopefully will be able to discern the state and
			# show it accordingly.
			#
		_download_format: ->
			@on 'click', 'td.formats a', (ev) ->
				ev.preventDefault()

				# We will return to the current page to handle errors
				x = encodeURIComponent window.location.href
				dl = @href
					.replace /\{errorpageurl\}/, x
					.replace /\{odreadauthurl\}/, x

				od.api dl
				.then(
					(x) ->
						window.open(
							od.proxy x.links.contentlink.href # url
							'_blank' #'Overdrive Read format' # title
							'resizable, scrollbars, status, menubar, toolbar, personalbar' # features
						)
					-> console.log 'failed to get download link'
				)
				.then(
					-> # not expected to arrive here ever
					-> console.log 'failed to get contentLink'
				)
				
				return


		_notify: (title, text) ->

			@dialog
				position: my: 'top', at: 'right top'
				minHeight: 0
				autoOpen: true
				draggable: false
				resizable: true
				show: effect: 'slideDown'
				hide: effect: 'slideUp'
				close: -> $(@).dialog 'destroy'
				title: title

			.text text

		# Get the title of e-item in a row context
		_etitle: -> @find('.title a').text()
