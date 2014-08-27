# Define custom jQuery extensions to rewrite content of existing pages
# None of the extensions directly use the API, but they depend on od_action which does.

define [
	'jquery'
	'lodash'
	'jquery-ui'
], ($, _) ->

	$.fn.extend

		# Append a list of formats from a metadata object to this container
		_show_formats: (x) ->
			return @ unless x

			$x =
				if x.formats
					$('<ul>')
						.css 'padding-left', '20px'
						.append _.map x.formats, (f) -> $('<li>').append f.name
				else
					$('<span>')
						.css 'color', 'red'
						.text 'No available formats'

			@append $x


		# Return an Overdrive product ID or null from a given DOM context.
		# The context can be represented as a jQuery object or as a selector string
		_productID: ->
			href = $('a[href*="downloads.bclibrary.ca"], a[href*="elm.lib.overdrive.com"]', @).attr('href')
			/ID=(.+)/.exec(href)?[1]

		# Modify search result row to show e-holdings (available formats and
		# copy status of an e-title) in a result_holdings_table
		_results: ->
			result = """
			<tr name="e_holdings" class="result_table_title_cell">
				<td colspan="2">
					<table class="result_holdings_table">
						<thead>
							<tr>
								<th>Available Formats</th>
								<th>Status</th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<td class="formats"></td>
								<td class="status"></td>
							</tr>
						</tbody>
					</table>
				</td>
			</tr>
			"""
			# For each result row that has an embedded Overdrive product ID
			ids = []
			for row in @ when id = $(row)._productID()

				# Cache the ID so that we don't need to traverse the DOM again
				ids.push id

				# Adorn each row with a product ID
				$(row).prop 'id', id
				# Add an empty container of format and availability values
				.find '.results_info_table > tbody'
					.append result
					.end()
				# Set up progress bars
				._results_meta()
				._results_avail()

			return ids

		_results_meta: (meta) ->
			status = if arguments.length is 0 then value: false else 'destroy'
			@find('.result_holdings_table .formats')
				.progressbar status
				._show_formats meta
				.end()

		_results_avail: (avail) ->
			status = if arguments.length is 0 then value: false else 'destroy'
			@find('.result_holdings_table .status')
				.progressbar status
				.end()

			return @ unless avail

			$x =
				if avail.available is undefined
					$('<span>')
						.css 'color', 'red'
						.text 'No longer available'
				else
					tpl = _.template """
					<span><%= n_avail %> of <%= n_owned %> available, <%= n_holds %> holds</span>
					"""
					$ tpl
						n_avail: avail.copiesAvailable
						n_owned: avail.copiesOwned
						n_holds:  avail.numberOfHolds

			@find('.result_holdings_table .status')
				.append $x
				.end()

		_record: ->

			# Find the product ID of this record
			id = @_productID()
			return unless id

			$record = $ """
			<div id="copy_hold_counts"><div id="#{id}">
				<span id="rdetail_copy_counts">
					<h2>Available formats</h2>
					<div class="formats"></div>
				</span>
				<span id="rdetail_hold_counts">
					<h2>Status</h2>
					<div class="status"></div>
				</span>
			</div></div>
			"""

			$record
				._record_meta()
				._record_avail()

			@after $record
			return id

		_record_meta: (meta) ->

			status = if arguments.length is 0 then value: false else 'destroy'
			@find '.formats'
				.progressbar status
				._show_formats meta
				.end()

		_record_avail: (avail) ->

			status = if arguments.length is 0 then value: false else 'destroy'
			@find '.status'
				.progressbar status
				.end()

			return @ unless avail

			$x =
				if avail.available is undefined
					$('<span>')
						.css 'color', 'red'
						.text 'No longer available'
				else
					tpl = _.template """
					<span><%= n_avail %> of <%= n_owned %> available, <%= n_holds %> holds</span>
					"""
					$ tpl
						n_avail: avail.copiesAvailable
						n_owned: avail.copiesOwned
						n_holds: avail.numberOfHolds

			@find '.status'
				.append $x
				.end()

		# Replace a place hold link with another link that is more relevant to
		# the availability of the title in a row context.
		_replace_place_hold_link: (avail, type_of_interest) ->
			return @ unless avail
			
			if avail.available is undefined
				@find '.place_hold'
					.remove()
					.end()

			# Find the place hold link that we want to replace
			$a = @find '.place_hold > a'

			# Parse the existing link text string for an indication of the item
			# format
			item_format = (text = $a.text()).match(/E-book/) or text.match(/E-audiobook/) or 'E-item'
			# Parse the existing link title for an item title, or if absent,
			# default to item format
			item_title = $a.prop('title').match(/on (.+)/)?[1] or item_format

			# Calculate the new text, title, and href properties, depending on
			# whether the user has an interest on the item and whether the item
			# is available or not
			[text, title, href] = switch type_of_interest

				# If the user has already placed a hold on the item,
				# we modify the link to go to the holds list
				when 'hold'
					[
						'Go to<br>E-items On Hold'
						'Go to E-items On Hold'
						'/eg/opac/myopac/holds?e_items'
					]

				# If the user has already checked out the item,
				# we modify the link to go to the checkout list
				when 'checkout'
					[
						'Go to<br>E-items Checked Out'
						'Go to E-items Checked Out'
						'/eg/opac/myopac/circs?e_items'
					]

				# If the user has no prior interest in the item, we modify the
				# link to go to the place hold form with the relevant query
				# parameters.
				else
					params = $.param
						e_items: 1
						interested: avail.id

					# The new text depends on avail.available and on the format, eg,
					# Place Hold on E-book
					# Place Hold on E-audiobook
					# Check Out E-book
					# Check Out E-audiobook
					verb = if avail.available then 'Check Out' else 'Place Hold on'
					url = if avail.available then '/eg/opac/myopac/circs' else '/eg/opac/myopac/holds'
					[
						"#{verb}<br>#{item_format}"
						"#{verb} #{item_title}"
						"#{url}?#{params}"
					]

			# Replacing the link means we have to do three things.
			$a
			# Change the title and href properties of the link
			.prop
				title: title
				href: href
			# Change the alt property of the link's image, which we equate to
			# the link's title property
			.find 'img'
				.prop 'alt', title
				.end()
			# Change the contents of the text label, which resides in a
			# container with two possible class names, depending on whether we
			# are on the results page or the record page
			.find '.result_place_hold, .place_hold'
				.replaceWith text
				.end()

			return @
