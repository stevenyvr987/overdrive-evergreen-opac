# This file represents a template to write a configuration module for the
# system.

define [
	'moment'
], (M) ->

	# Default configuration of date formats for Moment object;
	# see http://devdocs.io/moment/index#customization-long-date-formats
	M.lang 'en', longDateFormat:
        LT: "h:mm A"
        L:            "MM/DD/YYYY"
        LL:         "MMMM Do YYYY"
        LLL:        "MMMM Do YYYY LT"
        LLLL: "dddd, MMMM Do YYYY LT"

	# Mapping between long name of home library and Overdrive authorization name
	longname =
		'long name one': 'name1'
		'long name two': 'name2'

	return {

		# Define the credentials to use to get client authentication to the
		# API.  The text string is a combination of the client key and client
		# secret combined in the method described in
		# https://developer.overdrive.com/apis/client-auth, which can be
		# expressed by the following function:
		#
		# OAuthFormat = (key, secret) -> CryptoJS.enc.Base64.stringify CryptoJS.enc.Utf8.parse "#{key}:#{secret}"
		#
		credentials: '' # Base64 encoded text string

		# Define the credentials to use to get patron authentication, as described in
		# https://developer.overdrive.com/apis/patron-auth
		accountID: 4321
		websiteID:  321

		# Define the mapping function between long name and authorization name
		authorizationname: (id) -> longname[id]

		# Define whether a user password is required to complete patron authentication
		password_required: 'false' # or 'true'
	}
