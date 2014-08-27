// Build specification for the use of r.js to minify js files
// At the top-level directory, invoke as follows:
//
// # r.js -o build.js
//
({
	  appDir: './app' // un-minified input files
	, baseUrl: './' // location of modules relative to appDir
	, dir: './build' // minified output files

	// Define bundles of local modules
	, modules: [
		{ name: 'overdrive' }
	]

	// Define external resources (eg, not sourced locally,from content delivery networks, etc)
	, paths: {
		  jquery:   'empty:'
		, jqueryui: 'empty:'
		, lodash:   'empty:'
		, moment:   'empty:'
		, cookies:  'empty:'
		, json:     'empty:'
	}
})
