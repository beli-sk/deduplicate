#!/bin/bash
#
#	Deduplicate - "links" together duplicates on COW-enabled FS
#	Copyright 2011 Michal Belica <devel@beli.sk>
#
#	This program is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 3 of the License, or
#	(at your option) any later version.
#
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
# TODO:
#	- try to detect already "linked" files
#	- preserve xattrs

bksfx=".ddtmp$$"
prog=$( basename "$0" )
nodo=1

function cleanup {
	rm -f "$tmpfile"
}

function fail {
	echo "$prog fail: $1" >&2
	exit 1
}

function usage {
	echo "Deduplicate - \"links\" together duplicates on COW-enabled FS" >&2
	echo "Copyright 2011 Michal Belica <devel@beli.sk>" >&2
	echo "Licensed under the terms of the GNU General Public License" >&2
	echo "use: $prog <dir>" >&2
}

function dedup_file {
	local file1="$1" file2="$2"
	local bkfile="${file2}${bksfx}"
	echo "** Deduplicating $file2 from $file1 (backup $bkfile)"

	# check for backup file collision
	[[ -a "$bkfile" ]] && fail "backup file \"$bkfile\" already exists!"

	# compare the files
	if ! cmp "$file1" "$file2" ; then
		echo "Files differ, skiping."
		return
	fi

	# store ACLs
	getfacl "$file2" > "$tmpfile" || fail "getfacl"

	# make COW optimized copy
	cp -fb --reflink --suffix="$bksfx" "$file1" "$file2" || fail "copy"

	# sync attributes from backup of original file
	chown --reference="$bkfile" "$file2" || fail "chown"
	chmod --reference="$bkfile" "$file2" || fail "chmod"
	touch --reference="$bkfile" "$file2" || fail "touch"
	setfacl --restore="$tmpfile" || fail "setfacl"

	# remove backup of original file
	rm -f "$bkfile" || fail "rm"
}

if [[ -z "$1" ]] ; then
	usage
	exit 1
elif [[ ! -d "$1" ]] ; then
	usage
	fail "path \"$1\" not found"
fi

tmpfile=$( mktemp -t dedup_XXXXXX )
trap cleanup EXIT

echo "Finding duplicates..."

prevhash=""
find $@ -xdev -type f -print0 | xargs -0 cksum | sort \
		| while read line ; do
	fhash=$( echo $line | cut -d' ' -f1-2 )
	fname=$( echo $line | cut -d' ' -f3 )
	if [[ "$fhash" == "$prevhash" ]] ; then
		dedup_file $prevname $fname
	else
		prevhash="$fhash"
		prevname="$fname"
	fi
done
