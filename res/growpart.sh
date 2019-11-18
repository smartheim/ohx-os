#!/bin/sh
# Upstream: https://git.launchpad.net/cloud-utils/tree/bin/growpart
# Removed old kernel+partx check. Removed sgdisk alternative. Required tools: sfdisk, partx, blkid
# Expects util-linux>=2.30 (21-Sep-2017 09:51) and kernel > 4.0
#
#    Copyright (C) 2011 Canonical Ltd.
#    Copyright (C) 2013 Hewlett-Packard Development Company, L.P.
#
#    Authors: Scott Moser <smoser@canonical.com>
#             Juerg Haefliger <juerg.haefliger@hp.com>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, version 3 of the License.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

# the fudge factor. if within this many bytes dont bother
FUDGE=${GROWPART_FUDGE:-$((1024*1024))}
TEMP_D=""
RESTORE_FUNC=""
RESTORE_HUMAN=""
VERBOSITY=0
DISK=""
PART=""

MBR_BACKUP=""
GPT_BACKUP=""
_capture=""

error() {
	echo "$@" 1>&2
}

fail() {
	[ $# -eq 0 ] || echo "FAILED:" "$@"
	exit 2
}

bad_Usage() {
	error "$@"
	exit 2
}

nochange() {
	echo "NOCHANGE:" "$@"
	exit 1
}

changed() {
	echo "CHANGED:" "$@"
	exit 0
}

change() {
	echo "CHANGE:" "$@"
	exit 0
}

cleanup() {
	if [ -n "${RESTORE_FUNC}" ]; then
		error "***** WARNING: Resize failed, attempting to revert ******"
		if ${RESTORE_FUNC} ; then
			error "***** Restore appears to have gone OK ****"
		else
			error "***** Restore FAILED! ******"
			if [ -n "${RESTORE_HUMAN}" -a -f "${RESTORE_HUMAN}" ]; then
				error "**** original table looked like: ****"
				cat "${RESTORE_HUMAN}" 1>&2
			else
				error "We seem to have not saved the partition table!"
			fi
		fi
	fi
	[ -z "${TEMP_D}" -o ! -d "${TEMP_D}" ] || rm -Rf "${TEMP_D}"
}

debug() {
	local level=${1}
	shift
	[ "${level}" -gt "${VERBOSITY}" ] && return
	if [ "${DEBUG_LOG}" ]; then
		echo "$@" >>"${DEBUG_LOG}"
	else
		error "$@"
	fi
}

debugcat() {
	local level="$1"
	shift;
	[ "${level}" -gt "$VERBOSITY" ] && return
	if [ "${DEBUG_LOG}" ]; then
		cat "$@" >>"${DEBUG_LOG}"
	else
		cat "$@" 1>&2
	fi
}

mktemp_d() {
	# just a mktemp -d that doens't need mktemp if its not there.
	_RET=$(mktemp -d "${TMPDIR:-/tmp}/${0##*/}.XXXXXX" 2>/dev/null) &&
		return
	_RET=$(umask 077 && t="${TMPDIR:-/tmp}/${0##*/}.$$" &&
		mkdir "${t}" &&	echo "${t}")
	return
}

sfdisk_restore() {
	# files are named: sfdisk-<device>-<offset>.bak
	local f="" offset="" fails=0
	for f in "${MBR_BACKUP}"*.bak; do
		[ -f "$f" ] || continue
		offset=${f##*-}
		offset=${offset%.bak}
		[ "$offset" = "$f" ] && {
			error "WARN: confused by file $f";
			continue;
		}
		dd "if=$f" "of=${DISK}" seek=$(($offset)) bs=1 conv=notrunc ||
			{ error "WARN: failed restore from $f"; fails=$(($fails+1)); }
	done
	return $fails
}

sfdisk_worked_but_blkrrpart_failed() {
	local ret="$1" output="$2"
	# exit code found was just 1, but dont insist on that
	#[ $ret -eq 1 ] || return 1
	# Successfully wrote the new partition table
	if grep -qi "Success.* wrote.* new.* partition" "$output"; then
		grep -qi "BLKRRPART: Device or resource busy" "$output"
		return
	# The partition table has been altered.
	elif grep -qi "The.* part.* table.* has.* been.* altered" "$output"; then
		# Re-reading the partition table failed
		grep -qi "Re-reading.* partition.* table.* failed" "$output"
		return
	fi
	return $ret
}

resize_sfdisk() {
	local humanpt="${TEMP_D}/recovery"
	local mbr_backup="${TEMP_D}/orig.save"
	local format="$1"

	local change_out=${TEMP_D}/change.out
	local dump_out=${TEMP_D}/dump.out
	local new_out=${TEMP_D}/new.out
	local dump_mod=${TEMP_D}/dump.mod
	local tmp="${TEMP_D}/tmp.out"
	local err="${TEMP_D}/err.out"
	local mbr_max_512="4294967296"

	local pt_start pt_size pt_end max_end new_size change_info dpart
	local sector_num sector_size disk_size tot out

	rqe sfd_list sfdisk --list --unit=S "$DISK" >"$tmp" ||
		fail "failed: sfdisk --list $DISK"

	# --list first line output:
	# Disk /dev/vda: 20 GiB, 21474836480 bytes, 41943040 sectors
	local _x
	read _x _x _x _x disk_size _x sector_num _x  < "$tmp"
	sector_size=$((disk_size/$sector_num))

	debug 1 "$sector_num sectors of $sector_size. total size=${disk_size} bytes"

	rqe sfd_dump sfdisk --unit=S --dump "${DISK}" >"${dump_out}" ||
		fail "failed to dump sfdisk info for ${DISK}"
	RESTORE_HUMAN="$dump_out"

	{
		echo "## sfdisk --unit=S --dump ${DISK}"
		cat "${dump_out}"
	}  >"$humanpt"

	[ $? -eq 0 ] || fail "failed to save sfdisk -d output"
	RESTORE_HUMAN="$humanpt"

	debugcat 1 "$humanpt"

	sed -e 's/,//g; s/start=/start /; s/size=/size /' "${dump_out}" \
		>"${dump_mod}" ||
		fail "sed failed on dump output"

	dpart="${DISK}${PART}" # disk and partition number
	if [ -b "$DISK" ]; then
		if [ -b "${DISK}p${PART}" -a "${DISK%[0-9]}" != "${DISK}" ]; then
			# for block devices that end in a number (/dev/nbd0)
			# the partition is "<name>p<partition_number>" (/dev/nbd0p1)
			dpart="${DISK}p${PART}"
		elif [ "${DISK#/dev/loop[0-9]}" != "${DISK}" ]; then
			# for /dev/loop devices, sfdisk output will be <name>p<number>
			# format also, even though there is not a device there.
			dpart="${DISK}p${PART}"
		fi
	else
		case "$DISK" in
			# sfdisk for files ending in digit to <disk>p<num>.
			*[0-9]) dpart="${DISK}p${PART}";;
		esac
	fi

	pt_start=$(awk '$1 == pt { print $4 }' "pt=${dpart}" <"${dump_mod}") &&
		pt_size=$(awk '$1 == pt { print $6 }' "pt=${dpart}" <"${dump_mod}") &&
		[ -n "${pt_start}" -a -n "${pt_size}" ] &&
		pt_end=$((${pt_size}+${pt_start})) ||
		fail "failed to get start and end for ${dpart} in ${DISK}"

	# find the minimal starting location that is >= pt_end
	max_end=$(awk '$3 == "start" { if($4 >= pt_end && $4 < min)
		{ min = $4 } } END { printf("%s\n",min); }' \
		min=${sector_num} pt_end=${pt_end} "${dump_mod}") &&
		[ -n "${max_end}" ] ||
		fail "failed to get max_end for partition ${PART}"

	if [ "$format" = "gpt" ]; then
		# sfdisk respects 'last-lba' in input, and complains about
		# partitions that go past that.  without it, it does the right thing.
		sed -i '/^last-lba:/d' "$dump_out" ||
			fail "failed to remove last-lba from output"
	fi
	if [ "$format" = "dos" ]; then
		mbr_max_sectors=$((mbr_max_512*$((sector_size/512))))
		if [ "$max_end" -gt "$mbr_max_sectors" ]; then
			max_end=$mbr_max_sectors
		fi
		[ $(($disk_size/512)) -gt $mbr_max_512 ] &&
			debug 0 "WARNING: MBR/dos partitioned disk is larger than 2TB." \
				"Additional space will go unused."
	fi

	local gpt_second_size="33"
	if [ "${max_end}" -gt "$((${sector_num}-${gpt_second_size}))" ]; then
		# if mbr allow subsequent conversion to gpt without shrinking the
		# partition.  safety net at cost of 33 sectors, seems reasonable.
		# if gpt, we can't write there anyway.
		debug 1 "padding ${gpt_second_size} sectors for gpt secondary header"
		max_end=$((${sector_num}-${gpt_second_size}))
	fi

	debug 1 "max_end=${max_end} tot=${sector_num} pt_end=${pt_end}" \
		"pt_start=${pt_start} pt_size=${pt_size}"
	[ $((${pt_end})) -eq ${max_end} ] &&
		nochange "partition ${PART} is size ${pt_size}. it cannot be grown"
	[ $((${pt_end}+(${FUDGE}/$sector_size))) -gt ${max_end} ] &&
		nochange "partition ${PART} could only be grown by" \
		"$((${max_end}-${pt_end})) [fudge=$((${FUDGE}/$sector_size))]"

	# now, change the size for this partition in ${dump_out} to be the
	# new size
	new_size=$((${max_end}-${pt_start}))
	sed "\|^\s*${dpart} |s/\(.*\)${pt_size},/\1${new_size},/" "${dump_out}" \
		>"${new_out}" ||
		fail "failed to change size in output"

	change_info="partition=${PART} start=${pt_start}"
	change_info="${change_info} old: size=${pt_size} end=${pt_end}"
	change_info="${change_info} new: size=${new_size} end=${max_end}"

	MBR_BACKUP="${mbr_backup}"
	LANG=C sfdisk --no-reread "${DISK}" --force \
		-O "${mbr_backup}" <"${new_out}" >"${change_out}" 2>&1
	ret=$?
	[ $ret -eq 0 ] || RESTORE_FUNC="sfdisk_restore"

	if [ $ret -eq 0 ]; then
		debug 1 "resize of ${DISK} returned 0."
		if [ $VERBOSITY -gt 2 ]; then
			sed 's,^,| ,' "${change_out}" 1>&2
		fi
	elif sfdisk_worked_but_blkrrpart_failed "$ret" "${change_out}"; then
		# if the command failed, but it looks like only because
		# the device was busy and we have partx, then go on
		debug 1 "sfdisk failed, but likely only because of blkrrpart"
	else
		error "attempt to resize ${DISK} failed. sfdisk output below:"
		sed 's,^,| ,' "${change_out}" 1>&2
		fail "failed to resize"
	fi

	rq partx partx --update --nr "$PART" "$DISK" ||
		fail "pt_resize failed"

	RESTORE_FUNC=""

	changed "${change_info}"

	# dump_out looks something like:
	## partition table of /tmp/out.img
	#unit: sectors
	#
	#/tmp/out.img1 : start=        1, size=    48194, Id=83
	#/tmp/out.img2 : start=    48195, size=   963900, Id=83
	#/tmp/out.img3 : start=  1012095, size=   305235, Id=82
}

rq() {
	# runquieterror(label, command)
	# gobble stderr of a command unless it errors
	local label="$1" ret="" efile=""
	efile="$TEMP_D/$label.err"
	shift;

	local rlabel="running"
	[ "$1" = "would-run" ] && rlabel="would-run" && shift

	local cmd="" x=""
	for x in "$@"; do
		[ "${x#* }" != "$x" -o "${x#* \"}" != "$x" ] && x="'$x'"
		cmd="$cmd $x"
	done
	cmd=${cmd# }

	debug 2 "$rlabel[$label][$_capture]" "$cmd"
	[ "$rlabel" = "would-run" ] && return 0

	if [ "${_capture}" = "erronly" ]; then
		"$@" 2>"$TEMP_D/$label.err"
		ret=$?
	else
		"$@" >"$TEMP_D/$label.err" 2>&1
		ret=$?
	fi
	if [ $ret -ne 0 ]; then
		error "failed [$label:$ret]" "$@"
 		cat "$efile" 1>&2
	fi
	return $ret
}

rqe() {
	local _capture="erronly"
	rq "$@"
}

has_cmd() {
	command -v "${1}" >/dev/null 2>&1
}

has_cmd "sfdisk" || fail "sfdisk not found"
has_cmd "partx" || fail "partx not found"
has_cmd "blkid" || fail "blkid not found"

DISK=${1}
PART=${2}

[ -n "${DISK}" ] || bad_Usage "must supply disk and partition-number"
[ -n "${PART}" ] || bad_Usage "must supply partition-number"
[ -e "${DISK}" ] || fail "${DISK}: does not exist"

# If $DISK is a symlink, resolve it.
# This avoids problems due to varying partition device name formats
# (e.g. "1" for /dev/sda vs "-part1" for /dev/disk/by-id/name)
if [ -L "${DISK}" ]; then
	has_cmd readlink ||
		fail "${DISK} is a symlink, but 'readlink' command not available."
	real_disk=$(readlink -f "${DISK}") || fail "unable to resolve ${DISK}"
	debug 1 "${DISK} resolved to ${real_disk}"
	DISK=${real_disk}
fi

[ "${PART#*[!0-9]}" = "${PART}" ] || fail "partition-number must be a number"

mktemp_d && TEMP_D="${_RET}" || fail "failed to make temp dir"
trap cleanup EXIT

# get the ID of the first partition to determine if it's MBR or GPT
out=$(blkid -o value -s PTTYPE "$DISK")
if [ "$out" = "dos" -o "$out" = "gpt" ]; then
	format="$out"
else
	fail "Expected dos or gpt partion layout. Are you root? $out"
fi

if [ "$format" = "dos" ]; then
	resizer="resize_sfdisk dos"
fi
resizer="resize_sfdisk gpt"

debug 1 "resizing $PART on $DISK using $resizer"
$resizer

# vi: ts=4 noexpandtab
