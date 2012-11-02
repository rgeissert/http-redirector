#!/bin/sh

####################
#    Copyright (C) 2011, 2012 by Raphael Geissert <geissert@debian.org>
#
#    This file is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This file is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this file  If not, see <http://www.gnu.org/licenses/>.
#
#    On Debian systems, the complete text of the GNU General
#    Public License 3 can be found in '/usr/share/common-licenses/GPL-3'.
####################

set -eu

geoip=true
mirrors=true

while [ $# -gt 0 ]; do
    case "$1" in
	--geoip-only)
	    mirrors=false
	;;
	--mirrors-only)
	    geoip=false
	;;
	*)
	    echo "usage: $(basename "$0") [--geoip-only|--mirrors-only]" >&2
	    exit 1
	;;
    esac
    shift
done

if ! $geoip && ! $mirrors; then
    echo "nice try"
    exit 1
fi

if $geoip; then
    compression=gz
    if which unxz >/dev/null; then
	compression=xz
    fi

    mkdir -p geoip
    cd geoip
    for db in asnum/GeoIPASNum.dat.gz GeoLiteCity.dat.$compression asnum/GeoIPASNumv6.dat.gz GeoLiteCityv6-beta/GeoLiteCityv6.dat.gz; do
	wget -U '' -N http://geolite.maxmind.com/download/geoip/database/$db
	db="$(basename "$db")"
	case "$db" in
	    *.gz|*.xz)
		file_comp="${db##*.}"
	    ;;
	    *)
		echo "error: unknown compression of file $db" >&2
		exit 1
	    ;;
	esac

	decomp_db="${db%.$file_comp}"
	if [ -f $decomp_db ]; then
	    [ $db -nt $decomp_db ] || continue
	fi
	rm -f new.$db
	ln $db new.$db
	case "$file_comp" in
	    gz)
		gunzip -f new.$db
	    ;;
	    xz)
		unxz -f new.$db
	    ;;
	    *)
		echo "error: unknown decompressor for .$file_comp" >&2
		exit 1
	    ;;
	esac
	mv new.$decomp_db $decomp_db
	touch -r $db $decomp_db
    done
    cd - >/dev/null
fi

if $mirrors; then
    ./update.pl -j 15 --db-output db.wip
    ./check.pl -j 20 --db-store db.wip --db-output db.in --check-everything --disable-sites ''
fi
