The source code for the project is written in Coffeescript.

The source needs to be completed by writing a od_config.coffee file to define
configuration parameters, primarily related to authentication. Use the template
file 'od_config_template.coffee' by following its instructions.

The source also needs to be compiled into Javascript and minimized on a
development machine before executable code can be deployed on a production
server.


A. Prerequisites, development machine

1. Install nodejs.org

2. Install node packages
# sudo npm install --global coffee-script
# sudo npm install --global requirejs


B. Production Deployment

1. Put yourself at top-level project directory.

2. Compile source files from Coffeescript to Javascript

(long form)
# coffee --compile --bare --output app src

(short form)
# coffee -cb -o app src

3. Minify Javascript files
# r.js -o build.js

4. Deploy minified files to production server
# rsync -e 'ssh -l sitkastaff' -azv build/overdrive.js servername.domainname:/var/tmp

On production server:
# sudo chown opensrf:opensrf /var/tmp/overdrive.js
# sudo mv /var/tmp/overdrive.js /srv/openils/var/web/js/ui/default/opac


C. Configuration of Web Service

1. Add the following script tag to /srv/openils/var/templates/opac/parts/js.tt2.

<script type="text/javascript"
    src="https://cdnjs.cloudflare.com/ajax/libs/require.js/2.1.10/require.min.js"
    data-main="[% ctx.media_prefix %]/js/ui/default/opac/overdrive.js">
</script>

2. Define the file /etc/apache2/mods-available/proxy_http.conf, with the
following contents.

<IfModule mod_proxy_http.c>
    SSLProxyEngine On
    ProxyPass        /od/oauth        https://oauth.overdrive.com
    ProxyPassReverse /od/oauth        https://oauth.overdrive.com
    ProxyPass        /od/oauth-patron https://oauth-patron.overdrive.com
    ProxyPassReverse /od/oauth-patron https://oauth-patron.overdrive.com
    ProxyPass        /od/api          http://api.overdrive.com
    ProxyPassReverse /od/api          http://api.overdrive.com
    ProxyPass        /od/api-patron   http://patron.api.overdrive.com
    ProxyPassReverse /od/api-patron   http://patron.api.overdrive.com
    ProxyPass        /od/images       http://images.contentreserve.com
    ProxyPassReverse /od/images       http://images.contentreserve.com
    ProxyPass        /od/fulfill      http://fulfill.contentreserve.com
    ProxyPassReverse /od/fulfill      http://fulfill.contentreserve.com
</IfModule>

3. Ensure that the proxy_http module is enabled.

# cat /etc/apache2/mods-available/proxy_http.load
> LoadModule proxy_http_module /usr/lib/apache2/modules/mod_proxy_http.so

4. Gracefully restart the Apache web service.

# sudo service apache2 graceful


D. Web Browser

Reload the browser at http://libraryname.servername.domainname/eg/opac/home, to
run the home page of the OPAC.  Ensure that the browser's cache is disabled.
By monitoring the network traffic, you should see new JS and CSS files load, in
the following approximate sequence.

require.min.js
overdrive.js
jquery.min.js
lodash.min.js
cookies.min.js
json3.min.js
moment.min.js
jquery-ui.min.js
jquery-ui.min.css


E. Development Cycle

During development, you will cycle between compiling source files, deploying
unminified files, and testing.

- Run the compiler in watch mode and as a background process.

# coffee -cbw -o app src &

- Edit a file. It will be compiled automatically via the background process.

- Deploy unminified files in app directory to the test server.  (A convenient
  way is to upload the files to /var/tmp/od/ and to symbolically link each file
  to the target directory, /srv/openils/var/web/js/ui/default/opac.)

# rsync -e 'ssh -l sitkastaff' -azv app/ servername.domainname:/var/tmp/od

  On servername.domainname machine, repeat for each js files:

# sudo ln -s /var/tmp/od/overdrive.js /srv/openils/var/web/js/ui/default/opac

- Reload your browser, https://libraryname.servername.domainname, to run the
  modified files.  Ensure that the browser's cache is disabled.
