#!/bin/bash -e

# License: MIT
# David Graeff <david.graeff@web.de> - 2019

# Create void linux images via the build_one_arch script and move the compressed
# image files to ./releases. Parse the CHANGELOG file and create a new Github
# release according to the latest entry of that file, including new git tag and description.
# 
# Upload all ./releases images and attach them to the latest Github release.

readonly RELEASE_API_URL="https://api.github.com/repos/openhab-nodes/ohx-os/releases"
readonly UPLOAD_API_URL="https://uploads.github.com/repos/openhab-nodes/ohx-os/releases"

if [ -f github_token.inc ]; then
  source ./github_token.inc
fi

: "${GITHUB_TOKEN:=}"

build_one() {
	MACHINE="$1"
	ARCH="$2"
	BASEIMG="releases/ohx-$MACHINE-$ARCH.img.xz"
	mkdir -p releases
	if [ ! -f "$BASEIMG" ]; then
		say "Build $MACHINE - $ARCH"
		sh build_one_arch.sh $MACHINE $ARCH || err "Failed to build $MACHINE on $ARCH"
		mv "voidlinux/ohx-$MACHINE-$ARCH.img.xz" "$BASEIMG"
	fi
}

# Attach binary to Github release. Remove existing one if necessary.
# The filename pattern is: ohx-machine-tagname-sha256short.img.xz, eg: "ohx-rpi3-v1.0.0-aceac12.img.xz"
deploy() {
	local MACHINE="$1"
	local ARCH="$2"
	local LATEST_RELEASE="$3"

	local _file="releases/ohx-$MACHINE-$ARCH.img.xz"
	[ ! -f $_file ] && say "Skip non existing $_file" && return

	local MACHINE_ESC=$(echo $MACHINE | sed -e 's/-/_/g')
	
	local rel_id=$(echo $LATEST_RELEASE | jq -r ".id")
	local assets=$(echo $LATEST_RELEASE | jq -r '.assets[] | with_entries(select(.key == "id" or .key == "name")) | flatten | .[]')
	local sha=$(cat $_file| sha256sum -bz|cut -c -6)
	local current_tag=$(tagname)
	
	local is_done="0"
	
	# Do we need to deploy?
	IFS=' '
	while read -r asset_id; do
		read -r asset_name
		local asset_machine=$(echo $asset_name|cut -d "-" -f2)
		local asset_arch=$(echo $asset_name|cut -d "-" -f3)
		local asset_tagname=$(echo $asset_name|cut -d "-" -f4)
		local asset_sha=$(echo $asset_name|cut -d "-" -f5|cut -d "." -f1)
		local delete_url="$RELEASE_API_URL/assets/$asset_id"
		
		if [ "$asset_tagname" = "$current_tag" ] && [ "$asset_machine" = "$MACHINE_ESC" ] && [ "$asset_arch" = "$ARCH" ]; then
			if [ "$asset_sha" != "$sha" ]; then
				say "Checksums not equal. Reupload for $asset_machine ($asset_sha vs $sha). Old ID: $asset_id"
				curl -sSL -X DELETE "$delete_url" \
					-H "Accept: application/vnd.github.v3+json" \
					-H "Authorization: token $GITHUB_TOKEN" \
					-H "Content-Type: application/json"
			else
				say "Identical checksums. No need to redeploy $asset_machine for $ARCH"
				is_done="1"
			fi
			break
		fi
	done <<< $assets
	
	[ "$is_done" = "1" ] && return
		
	local mimetype=$(file --mime-type -b "$_file") 
	local upload_url="$UPLOAD_API_URL/$rel_id/assets"
	local basename="ohx-$MACHINE_ESC-$ARCH-$current_tag-$sha.img.xz"	
	local label="OHX $MACHINE Image ($basename)"
	#label=$(echo $label | curl -Gso /dev/null -w %{url_effective} --data-urlencode @- "" | cut -c 3-)
	say "Uploading $basename..."
	
	local _response=$(
		curl -SL -X POST \
			-H "Accept: application/vnd.github.manifold-preview" \
			-H "Authorization: token $GITHUB_TOKEN" \
			-H "Content-Type: $mimetype" \
			--data-urlencode "label=$label" \
			--data-binary "@$_file" "$upload_url?name=$basename" 
	)

	local _state=$(jq -r '.state' <<< "$_response")

	if [ "$_state" != "uploaded" ]; then
		err "Artifact not uploaded: $basename: $_response"
	else
		say "Uploaded!"
	fi
}

tagname() {
	cat CHANGELOG.md |grep -Po "v([0-9]{1,}\.)+[0-9]{1,}" -m 1
}

build_num() {
	git rev-parse HEAD
}

next_rel_title() {
	cat CHANGELOG.md | grep -Pzo '##.*\n\n\K\X*?(?=\n##|$)' | tr '\0' '\n' | head -n1
}

next_rel_body() {
	cat CHANGELOG.md | grep -Pzo '##.*\n\n\K\X*?(?=\n##|$)' | tr '\0' '\n' | sed '1d'
}

# Create Github release if not yet existing
make_release() {
	latest_release=$(curl -sSL "${RELEASE_API_URL}/latest" \
		-H "Accept: application/vnd.github.v3+json" \
		-H "Authorization: token $GITHUB_TOKEN" \
		-H "Content-Type: application/json")
		
	if [ "$(echo $latest_release | jq -r '.message')" = "Not Found" ]; then
		say "Latest release not found"
		need_new="1"
	else
		latest_ver=$(echo $latest_release | jq -r '.name')
		say "Latest release found: $latest_ver"
		[ "$latest_ver" != "$(next_rel_title)" ] && need_new="1"
	fi

	if [ ! -z "$need_new" ]; then
		say "Create new release: $(next_rel_title)"
		local _payload=$(
			jq --null-input \
				--arg tag "$(tagname)" \
				--arg name "$(next_rel_title)" \
				--arg body "$(next_rel_body)" \
				'{ tag_name: $tag, name: $name, body: $body, draft: false }'
		)

		curl -sSL -X POST "$RELEASE_API_URL" \
			-H "Accept: application/vnd.github.v3+json" \
			-H "Authorization: token $GITHUB_TOKEN" \
			-H "Content-Type: application/json" \
			-d "$_payload"
	fi
}

need_cmd() {
    if ! command -v "$1" > /dev/null 2>&1; then
        err "need '$1' (command not found) $2"
    fi
}

say() {
	local color=$( tput setaf 2 )
	local normal=$( tput sgr0 )
	echo "${color}$1${normal}"
}

err() {
	local color=$( tput setaf 1 )
	local normal=$( tput sgr0 )
	echo "${color}$1${normal}" >&2
	exit 1
}

need_cmd curl
need_cmd jq
need_cmd mkdir
need_cmd grep
need_cmd cat
need_cmd head
need_cmd sed
need_cmd basename
need_cmd file

if [ -z "$GITHUB_TOKEN" ]; then
	say "No github token set! Go to your Github account -> Developer Settings -> Tokens and create a new token."
	say "Store the new token in a file github_token.inc file as GITHUB_TOKEN=your_token"
	exit 0
fi

build_one uefi x86_64 || err "Failed to build x86_64"
build_one uefi aarch64 || err "Failed to build aarch64"
build_one beaglebone armv7l || err "Failed to build beaglebone"
build_one cubieboard2 armv7l || err "Failed to build cubieboard2"
build_one rpi2 armv7l || err "Failed to build rpi2"
build_one rpi3 aarch64 || err "Failed to build rpi3"
build_one odroid-c2 aarch64 || err "Failed to build odroid-c2"

make_release || err "Failed to create a Github release"

deploy uefi x86_64 "$latest_release"
deploy uefi aarch64 "$latest_release"
deploy beaglebone armv7l "$latest_release"
deploy cubieboard2 armv7l "$latest_release"
deploy rpi2 armv7l "$latest_release"
deploy rpi3 aarch64 "$latest_release"
deploy odroid-c2 aarch64 "$latest_release"
