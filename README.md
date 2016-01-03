Intro
=====

This is a work in progress. Please do send patches and provide feedback.
Thanks!

The project is similar to mirrorbrain (.org) and fedora's mirrors
system. However, it has a few differences (this list is not intended to
be complete):

* it is very specific to the way Debian mirrors are constructed.
  Details regarding architectures and the different mirror types are
  taken into consideration.
* because of the previous point and considering many mirrors only
  support http, it does not perform a full mirror scan. Mirrorbrain does.
  There's a tool to detect inconsistencies between what the mirrors master
  list claims a mirror contains and what it actually contains.
* it aims to be httpd-independent. Mirrorbrain requires apache.
* IPv6 support
* no DBMS. Although using a DBMS could provide some advantages, at the
  moment the Storable database seems to be enough. The idea is to keep
  everything simple.
* easy deployment

Live instance
=============

There's a live instance of this code (but not necessarily the latest
and greatest revision) at http://httpredir.debian.org/ (previously,
http.debian.net)

There's some more documentation there. It should be imported into the
repository, however.

TODO
====

There are some TODOs and FIXMEs in the source code, additionally,
there's the issues tracker at github:
https://github.com/rgeissert/http-redirector/issues

Getting started
===============

Required packages:
*    `moreutils`
*    `libanyevent-perl`
*    `libanyevent-http-perl`
*    `libev-perl` (recommended; or another event loop supported by AE)
*    `libtimedate-perl`
*    `libgeo-ip-perl`
*    `libwww-perl`
*    `liburi-perl`
*    `libplack-perl`
*    `liblinux-inotify2-perl` (for plackup -R, for local tests only)
*    `starman` (if using that server for the application)
*    `twiggy` (alternative server)
*    `wget`

Run `./update.sh`, it will download the geoip databases, the mirrors
list, build the database used by the redirector, and check the mirrors
for errors.

Look at the example below for invocation and plackup(1p) and Plack's
documentation for running the application under different server modes.

If you just want to simulate a request (like it used to be possible
with `redir.pl`), use `local-request.pl`. It sends a request to the
application without actually starting the server.
You can pass request parameters in the first argument to the script.
To fake the IP address of the request, set the `REMOTE_ADDR` env var when
calling it. No other CGI-like env var is recognised.

Getting started for development
===============================

Required packages (in addition to the ones above):
* `libtest-trap-perl`

Keeping everything in shape
===========================

update.sh should be run at least once a month[1], this allows the
changes to the mirror list(s) to be reflected. By default it will run:
 - `build-main-db.pl`
 - `build-peers-db.pl`
 - `check.pl`

`check.pl` should be run multiple times a day[2]

`build-peers-db.pl` should be run after every execution of
`build-main-db.pl` or whenever the peers lists are updated[3]

NOTE: update.sh will leave the new database in a file called `db.in`
to be renamed to `db` if it is the first time it is created. When
updating the db of an in-production instance, the new db will be picked up
by the next run of `check.pl`.

NOTE: `build-main-db.pl` and `check.pl` do NOT lock the database. You must
ensure that no more than one script is running at the same time.

[1] the script rebuilds the database, so any info collected by check.pl
regarding the availability of mirrors is lost.
check.pl --check-everything should be run after build-main-db.pl, this is
done automatically when running update.sh.

[2] it really depends on the kind of setup one wants and the hosts that
conform the mirrors network. For Debian's archive, it should be run
at least every ten minutes, every five minutes being better.

[3] it only applies when using an AS peers database. The name of the
peers database is specific to the mirrors database on which it is
based. At present, peers databases for old mirrors databases are not
cleaned up automatically.

Real life testing
=================

If using apache, you will want to run the redirector locally and make
apache forward the requests (therefore acting as a reverse proxy).
For example, if you run the application on port 5000 you can:

```apache
ProxyPass /redir http://127.0.0.1:5000/

RewriteEngine On
RewriteRule ^/?(?:(demo)/)?debian-(security|backports|ports)/(.*) /redir/?mirror=$2&url=$3&action=$1 [PT]
RewriteRule ^/?(?:(demo)/)?debian-archive/(.*) /redir/?mirror=old&url=$2&action=$1 [PT]
RewriteRule ^/?(?:(demo)/)?debian/(.*) /redir/?mirror=archive&url=$2&action=$1 [PT]

# mirror:// method support:
RewriteRule ^/?debian-(security|backports|ports)\.list(?:$|\?(.+)) /redir/?mirror=$1.list$2 [QSA,PT]
RewriteRule ^/?debian-archive\.list(?:$|\?(.+)) /redir/?mirror=old.list$1 [QSA,PT]
RewriteRule ^/?debian\.list(?:$|\?(.+)) /redir/?mirror=archive.list$1 [QSA,PT]
```

You can for example make it listen on 127.0.1.10, setup a vhost, and
use the following on your sources.list:

```sources.list
deb http://127.0.1.10/debian/ sid main
deb-src http://127.0.1.10/debian/ sid main

deb http://127.0.1.10/debian-security/ testing/updates main
deb http://security.debian.org/ testing/updates main
```

Note: accessing the redirector from a local IP address is not ideal and
may only work with hacks.

Forcibly disabling mirrors
==========================

If necessary, mirrors can forcibly be disabled by passing a file name
to `check.pl`'s `--disable-sites` option (`default: sites.disabled`)

The format of this file is:

```
<domain name>[/mirror type]
```

Whenever the option is passed and the file exists, every mirror
matching an entry in the file will be disabled without further checks.
If a mirror type is specified, only that mirror type of the given
mirror will be disabled.

An empty file name can be specified to override the default and to
prevent the parsing of said file. In order to re-enable a mirror an
existing file name must be specified.

NOTE: any disabled mirror that is no longer in the list will be
re-enabled. E.g. passing `--disable-sites /dev/null` to `check.pl` will
re-enable *all* disabled mirrors.

Running the redirector on top of a real mirror
==============================================

It is possible to run the redirector on a sever that has the files
itself. The use case would be: serve some users, send others to a
better mirror.

In order to use it in this mode, a few things need to be setup.

Mirror::Redirector:
* Set the `subrequest_method` variable as appropriate:
 - redirect: works on any httpd, but requires another roundtrip
 - sendfile: for apache with mod_xsendfile, lighttpd 1.5, cherokee
 - sendfile1.4: for lighttpd 1.4
 - accelredirect: for nginx
* Set the list of hosts for which the files will be served, in the
  `this_host` variable.
 For example, if your host is `my.mirror.tld`, that's what you need to
add.

NOTE: even though it is possible to list other mirror's host names,
care should be taken when doing so. The mirror checker is not aware of
this mapping and may lead to erroneous behaviour.

NOTE2: make sure your httpd works as expected. The redirector sends a
Content-Location header when the file should be delivered by the server
itself. Make sure it is not removed. Also look for issues with Range,
Last-Modified, and other features.

Then, setup your httpd so that requests for serve/ are served directly,
bypassing the redirector.
Finally, make all the usual traffic go through the redirector. Make
sure you don't break directory listing when doing so. mod_xsendfile,
for example, breaks it because it bypasses mod_autoindex.

A sample configuration for apache follows:

```apache
XSendFile On

# Should be possible to do it without an alias, but it makes it a
# bit clearer
Alias /debian/serve/ "/var/www/debian/"

RewriteEngine On
# Exclude /debian/serve/ from mod_rewrite, mod_alias will handle it
RewriteRule ^/?debian/serve/.*$ $0 [PT,L]
# Send all file requests through the redirector
RewriteRule ^/?debian/(.*[^/]$) /redir/?mirror=archive&url=$1 [NS,PT]
# Directory listing requests will pass-through and be handled by
# apache itself
```

IMPORTANT: do not enable this setup, or run the redirector at all, on a
mirror that is part of Debian's mirrors network without consulting the
mirroradmin group and WAITING for their APPROVAL.

AS peers database
=================

It is possible to instruct the redirector to serve clients from an
originating AS to one or a set of destination AS' where mirrors are
located. The database can be built with the build-peers-db.pl script.

Its input are \*.lst files in the peers.lst.d directory in the following
format:

```
<client AS> <mirror domain name|mirror AS> [distance [IPv]]
```

The preferred form of the second value is by domain name. When an AS is
specified, it will internally be rewritten to the existing mirrors in
the corresponding AS.

Comments may be specified by prefixing them with a `#` character.
Multiple client ASNs can be specified by enclosing them in braces and
separating them with commas. E.g. `{13138,2210} some.mirror.tld`

The distance is currently not used by the redirector, but at some point
it might. It defaults to 0. Any positive integer may be specified.
It is expected to be read as 0 being the most preferred mirror, 1 being
the second, 2 being the third, and so on.

The IPv field, if specified, should be `v4`, `v6`, or the two separated
by a comma with no specific order. It can be used to indicate that the
given peering rule only applies to the version of the IP specified in
the field. It defaults to `v4`.

Mirrors chosen by this database are still subject to geo location
restriction. I.e. from the set of candidates, a subset of those that
are geographically closer will be created and used.

Caveats: since the database is AS-based, large Autonomous Systems that
traverse countries or continents will still be considered, even if not
desired. At present, the redirector skips mirrors that are located in a
different continent, but that's done to work around another issue and
the behaviour is not guaranteed to persist after the other issue is
properly addressed.

Understanding the db
====================

The database consists of (mostly inverted) indexes that are supposed to
provide fast and cheap lookups.

In order to save space on the database, a few unusual things are done.
For example, hash entries with `undef` as value are valid. `undef` is
smaller in a Storable database than an integer.
Any script using the database should therefore test for 'exists' instead
of 'defined'.

To better understand what the database looks like, run ./dump-db.pl | pager

Credits
=======

"This product includes GeoLite data created by MaxMind, available from
http://maxmind.com/"
