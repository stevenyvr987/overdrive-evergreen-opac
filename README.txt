The source code for the project is written Coffeescript.

The source needs to be completed by writing a od_config.coffee file to define
configuration parameters, primarily related to authentication. Use the template
file 'od_config_template.coffee' by following the instructions in the comments.

The source also needs to be compiled into Javascript and minimized before the
code can be deployed on a production server.

Prerequisites

1. Install nodejs.org

2. Install node packages
# npm install --global coffee-script
# npm install --global requirejs


Production Deployment

1. Put yourself at top-level project directory.

2. Compile source files from Coffeescript to Javascript (long form)
# coffee --compile --bare --output app src

(short form)
# coffee -cb -o app src

3. Minify Javascript files
# r.js -o build.js

4. Deploy minified files
# rsync -e 'ssh -l sitkastaff' -azv build/overdrive.js servername.domainname:/var/tmp/od


Development

During development, you will cycle between compiling source files, deploying
unminified files, and testing.

- Run the compiler in watch mode and as a background process.
# coffee -cbw -o app src &

- Edit a file. It will be compiled automatically via the background process.

- Deploy unminified files that have been modified to the test server.
# rsync -e 'ssh -l sitkastaff' -azv app/ servername.domainname:/var/tmp/od

- Reload your browser, https://libraryname.servername.domainname, to run the
  modified file.  Ensure that the browser's cache is disabled. 
