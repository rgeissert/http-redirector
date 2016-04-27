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
peers=true
bgp=false

while [ $# -gt 0 ]; do
    case "$1" in
	--geoip-only)
	    mirrors=false
	    peers=false
	;;
	--mirrors-only)
	    geoip=false
	    peers=false
	;;
	--peers-only)
	    mirrors=false
	    geoip=false
	;;
	--bgp-only)
	    mirrors=false
	    geoip=false
	    peers=false
	    bgp=true
	;;
	*)
	    echo "usage: $(basename "$0") [--geoip-only|--mirrors-only|--peers-only|--bgp-only]" >&2
	    exit 1
	;;
    esac
    shift
done

if ! $geoip && ! $mirrors && ! $peers && ! $bgp; then
    echo "nice try"
    exit 1
fi

dir=/etc/ssl/ca-debian
if [ -d $dir ]; then
    cadebian="--ca-directory=$dir"
else
    cadebian=
fi

dir=/etc/ssl/ca-global
if [ -d $dir ]; then
    caglobal="--ca-directory=$dir"
else
    caglobal=
fi

if $geoip; then
    compression=gz
    if which unxz >/dev/null; then
	compression=xz
    fi

    mkdir -p geoip
    cd geoip
    for db in asnum/GeoIPASNum.dat.gz GeoLiteCity.dat.$compression asnum/GeoIPASNumv6.dat.gz GeoLiteCityv6-beta/GeoLiteCityv6.dat.gz; do
	wget $caglobal -U '' -N https://geolite.maxmind.com/download/geoip/database/$db
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

if $bgp; then
    mkdir -p bgp
    echo "Using bgp/ as cwd"
    cd bgp

    zdp=zebra-dump-parser/zebra-dump-parser.pl
    [ -x $zdp ] || {
	echo "error: couldn't find an executable zdp at $zdp" >&2
	exit 1
    }
    if [ -n "$(sed -rn '/^my\s+\$ignore_v6_routes\s*=\s*1/p' $zdp)" ]; then
	echo "warning: ipv6 routes are ignored by zdp, trying to fix it" >&2
	sed -ri '/^my\s+\$ignore_v6_routes\s*=\s*1/{s/=\s*1/= 0/}' $zdp
    fi

    wget -N http://data.ris.ripe.net/rrc00/latest-bview.gz
    zdpout="zdp-stdout-$(date -d "$(stat -c%y latest-bview.gz)" +%F)"

    echo "warning: expanding bgp dump to $zdpout, can take some 400MB" >&2
    zcat latest-bview.gz | $zdp > "$zdpout"

    cd - >/dev/null

    echo "Going to extract peers, resume with the following commands:"
    command="
    ./extract-peers.pl --progress < 'bgp/$zdpout'
    sort -u peers.lst.d/routing-table.lst | LC_ALL=C sort -n | sponge peers.lst.d/routing-table.lst
"
    echo "$command"
    eval "$command"
fi

if $peers; then
    if [ -z "$(find peers.lst.d/ -name '*.lst')" ]; then
	peers=false
    elif [ -f db ]; then
	./build-peers-db.pl
    fi
fi

if $mirrors; then

    cd mirrors.lst.d
    wget $cadebian -O Mirrors.masterlist.new \
	'https://anonscm.debian.org/viewvc/webwml/webwml/english/mirror/Mirrors.masterlist?view=co'
    mv Mirrors.masterlist.new Mirrors.masterlist
    cd - >/dev/null

    ./build-main-db.pl --db-output db.wip
    if $peers; then
	./build-peers-db.pl --mirrors-db db.wip
    fi
    ./check.pl --db-store db.wip --db-output db.in --check-everything --disable-sites '' |
	./translate-log.pl
fi
