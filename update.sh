#!/bin/sh

####################
#    Copyright (C) 2011 by Raphael Geissert <geissert@debian.org>
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

set -e

mkdir -p geoip
cd geoip
for db in asnum/GeoIPASNum.dat.gz GeoLiteCity.dat.gz asnum/GeoIPASNumv6.dat.gz GeoLiteCityv6-beta/GeoLiteCityv6.dat.gz; do
    wget -U '' -N http://geolite.maxmind.com/download/geoip/database/$db
    db="$(basename "$db")"
    if [ -f ${db%.gz} ]; then
	[ $db -nt ${db%.gz} ] || continue
    fi
    rm -f new.$db
    ln $db new.$db
    gunzip -f new.$db
    db=${db%.gz}
    mv new.$db $db
    touch -r $db.gz $db
done
cd - >/dev/null

./update.pl -j 15 --leave-new
./check.pl --db-store db.new --db-output db --check-architectures --check-areas
