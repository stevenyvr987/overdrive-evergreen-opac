# Define custom jQuery extensions to rewrite content of existing pages
# None of the extensions directly use the API, but they depend on od_action which does.

define [
	'jquery'
	'lodash'
	'jquery-ui'
	'od_action'
	'od_pages_opac'
], ($, _) ->

	$.fn.extend

		# Given a map between classnames and numeric values,
		# eg, { class1: 1, class2: -1 },
		# increment the existing values of the containers with the classnames.
		_counters: (x) ->
			for n, v of x
				$x = @find ".#{n}"
				$x.text +($x.text()) + v
			return @

		_dashboard: (x) ->

			if arguments.length is 0
				@append $('<div id="dashboard">')

			else
				# Add a new dashboard for to show counts of e-items; start with
				# zero counts
				base = '/eg/opac/myopac'
				@find 'div'
					.eq 2
					.append """
					<span class="dash-align">
						<a class="dash-link" href="#{base}/circs?e_items"><span class="ncheckouts" id="dash_checked">0</span> E-items Checked Out</a>
					</span>
					<span class="dash_divider">|</span>
					<span class="dash-align">
						<a class="dash-link" href="#{base}/holds?e_items"><span class="nholds" id="dash_holds">0</span> E-items on Hold</a>
					</span>
					<span class="dash_divider">|</span>
					<span class="dash-align">
						<a class="dash-link" href="#{base}/holds?e_items&available=1"><span class="nholdsready" id="dash_pickup">0</span> E-items Ready for Checkout</a>
					</span>
					"""
					.end()
					.end()

				# The following sequence is necessary to align the new dashboard
				# with the existing ones, but do not know why it needs to be done
				@find 'div'
					.css float: 'none'
					.end()

				@_counters x # Change the values of the counters

			return @

		# Replace account summary area with one that shows links to go to
		# physical and e-items lists
		_account_summary: (x) ->

			if arguments.length is 0
				# Parse a list of totals of physical items from the account summary table
				totals = ( +(v.textContent.match(/\d+?/)[0]) for v in @find('td').not '[align="right"]' )

				tpl = _.template """
				<tbody>
					<tr>
						<td>
							<a href="/eg/opac/myopac/circs">
								<span><span class="ncheckouts" /> <%= ncheckouts %> Items Currently Checked out</span>
							</a>
						</td>
						<td align="right">
							<a href="/eg/opac/myopac/circs?e_items"><span class="n_checkouts" /> E-items Currently Checked out</a>
						</td>
					</tr>
					<tr>
						<td>
							<a href="/eg/opac/myopac/holds"><span class="nholds" /> <%= nholds %> Items Currently on Hold</a>
						</td>
						<td align="right">
							<a href="/eg/opac/myopac/holds?e_items"><span class="n_holds" /> E-items Currently on Hold</a>
						</td>
					</tr>
					<tr>
						<td>
							<a href="/eg/opac/myopac/holds?available=1"><span class="nready" /> <%= nready %> Items ready for pickup</a>
						</td>
						<td align="right">
							<a href="/eg/opac/myopac/holds?e_items&available=1"><span class="n_ready" /> E-items ready for pickup</a>
						</td>
					</tr>
				</tbody>
				"""

				# Build a new table consisting of two columns.  The first
				# column is for physical items with the existing totals.  The
				# second column is for e-items and is initially hidden until
				# its total values are available.
				@empty()
				.append tpl
					ncheckouts:  totals[0]
					nholds:	     totals[1]
					nready:	     totals[2]
				.find 'td'
					.filter '[align="right"]'
					.find 'a'
						.hide()
						.end()
					.end()

			else
				# Change the values of the counters and reveal the e-items column
				@_counters x
				.find 'td'
					.filter '[align="right"]'
					.find 'a'
						.show()
						.end()
					.end()

		# Relabel a history tab
		_tab_history: ->
			$x = $('a', @)
			$x.text "#{ $x.text() } (Physical Items)"
			return @

		# Add a new tab for e-items and select a tab relevant for the current page name.
		# If page name contains 'history' then select any tabs with 'history' in its ID
		# otherwise, if search parameters has 'e_items' property then select any tabs with 'eitems' in its ID
		#$('#acct_holds_tabs, #acct_checked_tabs')._etabs()
		_etabs: (page_name, e_items) ->

			# Tab replacement is identified by container's id
			new_tabs =
				acct_holds_tabs: """
				<div id="acct_holds_tabs">
					<div class="align" id='tab_holds'>
						<a href="holds#">Items on Hold</a>
					</div>
					<div class="align" id='tab_holds_eitems'>
						<a href="holds?e_items">E-items on Hold</a>
					</div>
					<div class="align" id='tab_holds_history'>
						<a href="hold_history">Holds History</a>
					</div>
				</div>
				"""
				acct_checked_tabs: """
				<div id="acct_checked_tabs">
					<div class="align" id='tab_circs'>
						<a href="circs#">Current Items Checked Out</a>
					</div>
					<div class="align" id='tab_circs_eitems'>
						<a href="circs?e_items">E-items Checked Out</a>
					</div>
					<div class="align" id='tab_circs_history'>
						<a href="circ_history">Check Out History</a>
				   </div>
				</div>
				"""
			@replaceWith new_tabs[@prop 'id']

			# Compute the selected tab of the current page name
			$selected =
				# if page name ends with '_history', select the tab with id
				# that ends with '_history'
				if /_history$/.test page_name
					$('[id$=_history]')
				# else if search parameters has 'e_items' property, select the
				# tab with id that ends with '_eitems'
				else if e_items
					$('[id$=_eitems]')
				# else select the remaining tab
				else
					$('[id^=tab_]').not '[id$=_history],[id$=_eitems]'

			$selected.addClass 'selected'

			return @


		# Resize columns of a table, either to fixed widths, or to be equal
		# widths, ie, 100% divided by number of columns.
		# Also, force width of table to 100%; don't know why this is necessary.
		_resizeCols: ->

			$table = @find 'table'
				.css 'width', '100%'

			# Resize to percentage widths given in the argument list
			if arguments.length > 0
				$th = $table.find 'th'
				$td = $table.find 'td'
				for width, n in arguments
					$th.eq(n).css 'width', width
					$td.eq(n).css 'width', width

			# Otherwise, resize to equal widths
			else
				ncols = @find('th').length or 1
				width = "#{100 / ncols}%"

				$table
				.find 'th'
					.css 'width', width
					.end()
				.find 'td'
					.css 'width', width
					.end()

			return @

		# Show a container having a class name from a list of candidate, and hide the rest
		_show_from: (which, candidates...) ->

			@find(x).hide() for x in candidates
			@find candidates[which]
				.show()
				.end()

		# Replace a title of table with new text
		_replace_title: (x) ->

			@find '.header_middle span'
				.eq 0
				.text x
				.end()

		# Build an empty table for showing a list of holds
		_holds_main: ->

			table = """
				<table cellpadding="0" cellspacing="0" border="0">
					<thead id="acct_holds_main_header"><tr>
						<th></th>
						<th>Title/Author</th>
						<th>Availability</th>
						<th>Formats</th>
						<th>Actions</th>
					</tr></thead>
					<tbody id="holds_temp_parent"></tbody>
				</table>
				<div class="warning_box">No holds found.</div>
			"""
			@empty().append table
			._resizeCols '15%', '20%', '30%', '20%', '15%'

		# Build <tr> elements for showing a list of holds
		_holds_rows: (holds) ->
			return [] unless holds

			tpl = _.template """
			<tr id="<%= id %>" name="acct_holds_temp" class="acct_holds_temp inactive-hold">
				<td class="thumbnail"></td>
				<td>
					<div class="title" /> by <div class="author" />
				</td>
				<td class="availability"></td>
				<td class="formats"></td>
				<td class="actions"></td>
			</tr>
			"""

			ids = []
			$rows = for hold in holds

				ids.push hold.reserveId

				# Build an empty row element that is uniquely identified by a
				# product ID
				$row = $ tpl id: hold.reserveId

				# Fill the row with hold values and proxy the rest of the row
				# with progress bars
				$row
					._holds_row hold # hold values
					._row_meta() # progress bar
					._holds_row_avail() # progress bar

			# Add hold rows to <tbody> and remove the warning box.
			if $rows.length > 0
				@find 'tbody'
					.empty().append $rows
					.end()
				.find '.warning_box'
					.remove()
					.end()

			return ids

		_holds_row: (hold) ->

			@find 'td.availability'
				._holds_row_avail1 hold
				.end()
			.find 'td.actions'
				._actions hold.actions, hold.reserveId
				.end()

		# Show a title, author, or format by using the given metadata object
		_row_meta: (meta, classnames...) ->

			status = if arguments.length is 0 then value: false else 'destroy'
			try @find(".#{n}").progressbar(status) for n in ['title', 'author', 'formats']

			return @ unless meta

			$title = $ """
			<a href="/eg/opac/results?query=#{meta.title};locg=10;qtype=title">#{meta.title}</a>
			"""
			$thumbnail = $ """
			<img src="#{meta.images?.thumbnail?.href}" alt="#{meta.title}" />
			"""
			$author = $ """
			<a href="/eg/opac/results?query=#{meta.author};locg=10;qtype=author">#{meta.author}</a>
			"""
			for n in classnames
				$n = @find ".#{n}"
				switch n
					when 'thumbnail' then $n.empty().append $thumbnail
					when 'title'     then $n.empty().append $title
					when 'author'    then $n.empty().append $author
					when 'formats'   then $n._show_formats meta?.formats
			return @

		_holds_row_avail1: (hold) ->

			hold_status = if hold.holdSuspension then 0 else if hold.actions.checkout then 1 else 2

			x = if hold.holdSuspension?.suspensionType is 'limited' then 'show' else 'hide'

			tpl = _.template """
			<div class="suspended">
				<div style="color: red">Suspended <span class="limited">until <%= activates %></span></div>
				<ul style="padding-left: 20px">
				<li name="acct_holds_status"><%= position %> / <%= nHolds %> holds <span class="copies" /></li>
				<li>Email notification will be sent to <%= email %></li>
				<li>Hold was placed <%= placed %></li>
				</ul>
			</div>
			<div class="unavailable">
				<div>Waiting for copy</div>
				<ul style="padding-left: 20px">
				<li name="acct_holds_status"><%= position %> / <%= nHolds %> holds <span class="copies" /></li>
				<li>Email notification will be sent to <%= email %></li>
				<li>Hold was placed <%= placed %></li>
				</ul>
			</div>
			<div class="available">
				<div style="color: green">Ready for checkout</div>
				<ul style="padding-left: 20px">
				<li name="acct_holds_status"><%= position %> / <%= nHolds %> holds <span class="copies" /></li>
				<li>Hold will expire <%= expires %></li>
				</ul>
			</div>
			<a href="http://downloads.bclibrary.ca/ContentDetails.htm?ID=<%= id %>">Link to Overdrive Account to change preferences</a>
			"""
			@empty().append tpl
				position:  hold.holdListPosition
				nHolds:    hold.numberOfHolds
				email:     hold.emailAddress
				expires:   hold.holdExpires.fromNow()
				placed:    hold.holdPlacedDate.fromNow()
				activates: hold.holdSuspension?.numberOfDays.calendar()
				id:        hold.reserveId

			# Illuminate areas of this row according to the hold status
			._show_from hold_status, '.suspended', '.available', '.unavailable'
			# Show the hold suspension date only if suspension type is limited
			.find('.limited')[x]()
				.end()

		# Complete building a <tr> element for showing a hold by using the
		# given availability object
		_holds_row_avail: (avail) ->

			status = if arguments.length is 0 then value: false else 'destroy'
			@find '.copies'
				.progressbar status
				.end()

			return @ unless avail

			text = """
			on #{avail.copiesOwned} copies
			"""
			@find '.copies'
				.text text
				.end()

		# Build an empty table for showing a list of checkouts
		_checkouts_main: ->

			table = """
				<table cellpadding="0" cellspacing="0" border="0">
					<thead id="acct_checked_main_header"><tr>
						<th></th>
						<th>Title/Author</th>
						<th>Availability</th>
						<th>Formats</th>
						<th>Actions</th>
					</tr></thead>
					<tbody id="holds_temp_parent"></tbody>
				</table>
				<div class="warning_box">No checkouts found.</div>
			"""
			@empty().append table
			._resizeCols()

		# Build <tr> elements for showing a list of checkouts
		_checkouts_rows: (circs) ->
			return [] unless circs

			tpl = _.template """
			<tr id="<%= id %>" name="acct_checked_temp" class="acct_checked_temp inactive-hold">
				<td class="thumbnail"></td>
				<td>
					<div class="title" /> by <div class="author" />
				</td>
				<td class="availability"></td>
				<td class="formats"></td>
				<td class="actions"></td>
			</tr>
			"""

			ids = []
			$rows = for circ in circs

				ids.push circ.reserveId

				# Build an empty row element that is uniquely identified by a
				# product ID
				$row = $ tpl id: circ.reserveId

				# Fill the row with circ values and proxy the rest of the row
				# with progress bars
				$row
					._row_checkout circ # circ values
					._row_meta() # progress bars

			# Add checkout rows to <tbody> and remove the warning box.
			if $rows.length > 0
				@find 'tbody'
					.empty().append $rows
					.end()
				.find '.warning_box'
					.remove()
					.end()

			return ids

		_row_checkout: (circ) ->

			@find 'td.availability'
				._checkouts_row_avail circ
				.end()
			.find 'td.actions'
				._actions circ.actions, circ.reserveId
				.end()
			.find 'td.formats'
				._formats circ.formats, circ.reserveId
				.end()

		_checkouts_row_avail: (circ) ->

			tpl = _.template """
			<div>Expires <%= expires_relatively %></div>
			<div><%= expires_exactly %></div>
			<a href="http://downloads.bclibrary.ca/ContentDetails.htm?ID=<%= id %>">Click to access online (library card required)</a>
			"""
			@empty().append tpl
				expires_relatively: circ.expires.fromNow()
				expires_exactly:    circ.expires.format 'YYYY MMM D, h:mm:ss a'
				id:                 circ.reserveId

		# Build a <tr> element to show the available actions of an item.
		# If the item is available, the check out action should be possible,
		# and if unavailable, the place hold action should be possible.
		_holdings_row: (id) ->

			tpl = _.template """
			<tr id="<%= id %>" name="acct_holds_temp" class="acct_holds_temp inactive-hold">
				<td class="thumbnail"></td>
				<td>
					<div class="title" /> by <div class="author" />
				</td>
				<td class="availability"></td>
				<td class="formats"><ul></ul></td>
				<td class="actions"></td>
			</tr>
			"""
			$row = $(tpl id: id)
				._row_meta() # progress bar
				._holdings_row_avail() # progress bar

			@find 'tbody'
				.empty().append $row
				.end()
			.find '.warning_box'
				.remove()
				.end()

		# Complete building a <tr> element for a holding using the given availability object
		_holdings_row_avail: (avail) ->

			# Create or destroy progress bars
			status = if arguments.length is 0 then value: false else 'destroy'
			@find 'td.availability'
				.progressbar status
				.end()
			.find 'td.actions'
				.progressbar status
				.end()

			return @ unless avail

			tpl = _.template """
			<div class="unavailable">No copies are available for checkout</div>
			<div class="available" style="color: green">A copy is available for checkout</div>
			<div><%= n_avail %> of <%= n_owned %> available, <%= n_holds %> holds</div>
			"""
			@find 'td.availability'
				.append tpl
					n_owned: avail.copiesOwned
					n_avail: avail.copiesAvailable
					n_holds: avail.numberOfHolds
				.end()

			# Build action buttons
			.find 'td.actions'
				._actions avail.actions, avail.id
				.end()

			# Illuminate areas of this row according to the holdings status
			._show_from (if avail.available then 0 else 1), '.available', '.unavailable'

