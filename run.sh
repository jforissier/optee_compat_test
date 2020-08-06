#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
#
# OP-TEE backward compatibility testing helper script
#
# This scripts fetches and builds two versions of OP-TEE, "old" and "new", then
# it creates a hybrid environment which is a copy of the "new" OP-TEE with a
# copy of the "old" xtest binaries (CA and TAs). The tests are run in there
# ("make check"). If the tests pass, it means the newer OP-TEE has not broken
# compatibility with older TAs.

OLD_V=3.8.0
OLD_URL=https://github.com/OP-TEE/manifest.git

NEW_V=master
NEW_URL=https://github.com/OP-TEE/manifest.git

# Work directory (where everything is cloned and built)
O=out

##

OLD=$O/old-$OLD_V
NEW=$O/new-$NEW_V
HYBRID=$O/hybrid # Copy of NEW with xtest binaries from OLD

function warn() {
	echo "### $*"
}

function errx() {
	exit 1
}

function get_repo() {
	mkdir -p $O
	curl https://storage.googleapis.com/git-repo-downloads/repo >$O/repo && chmod +x $O/repo
}

# $1 'old' or 'new'
function clone() {
	local branch
	local args
	local out
	local url

	case $1 in
	old)
		out=$OLD
		url=$OLD_URL
		branch=$OLD_V
		;;
	new)
		out=$NEW
		url=$NEW_URL
		branch=$NEW_V
		;;
	*)
		errx
		;;
	esac

	if [ -e $out ]; then
		return
	fi
	mkdir -p $out
	pushd .
	cd $out
	case $branch in
	master)
		;;
	*)
		args="-b $branch"
		;;
	esac
	../repo init -u $url $args || errx
	../repo sync -j20 --no-clone-bundle
	popd
}

# $1 make target or nothing
function make_helper() {
	make -j2 toolchains
	# gcc 9.3.0 Ubuntu 20.04
	# usr/bin/ld: soc_term.o: relocation R_X86_64_32 against `.rodata.str1.1' can not be used when making a PIE object; recompile with -fPIE
	make soc-term CFLAGS=-fPIE
	make -j10 $1 || errx
}

# Note:
# The 'current' symlink is supposed to help avoid useless rebuilds in 'hybrid'
# which is essentially a copy of 'new'. Not sure it works well, but not super
# important either.
function changedir() {
	case $1 in
	old)
		cd $OLD/build
		;;
	new)
		rm -f $O/current
		ln -s new-$NEW_V $O/current
		cd $O/current/build
		;;
	hybrid)
		rm -f $O/current
		ln -s hybrid $O/current
		cd $O/current/build
		;;
	*)
		errx
		;;
	esac
}

# $1 'old' or 'new'
# $2 'check' or empty
function _make() {
	pushd .
	changedir $1
	make_helper $2
	popd
}

function copy_old_apps() {
	local bn

	TA_LIST=$(find $OLD/out-br/build -name \*.ta)
	for ta in $TA_LIST ; do
		bn=$(basename $ta)
		dest=$(find $HYBRID/out-br/build -name $bn)
		if [ "$dest" ]; then
			cp -f $ta $dest
		else
			warn "TA $bn ($ta) not found in $NEW"
		fi
	done
	old_xtest=$(find $OLD/out-br/host -name xtest)
	dest_xtest=$(find $HYBRID/out-br/build -name xtest -a -type f)
	cp -f $old_xtest $dest_xtest
}

set -x

get_repo

clone old
clone new
_make old
_make new
rsync -a $NEW/ $HYBRID

# No doubt this "make; copy; make" sequence is fragile, but it works
_make hybrid
copy_old_apps
_make hybrid check
