#!/bin/bash

# This file is "source"d into another.
# "${CURRENT_IMAGE}" is the name of the current image we're working on.

ME="$(basename "${BASH_ARGV0}")"

# Subtract dark frame if there is one defined in config.sh
# This has to come after executing darkCapture.sh which sets ${TEMPERATURE}.

if [ "${DARK_FRAME_SUBTRACTION}" = "true" ]; then
	# Make sure the input file exists; if not, something major is wrong so exit.
	if [ "${CURRENT_IMAGE}" = "" ]; then
		echo "*** ${ME}: ERROR: 'CURRENT_IMAGE' not set; aborting."
		exit 1
	fi
	if [ ! -f "${CURRENT_IMAGE}" ]; then
		echo "*** ${ME}: ERROR: '${CURRENT_IMAGE}' does not exist; aborting."
		exit 2
	fi

	# Make sure we know the current temperature.
	# If it doesn't exist, warn the user but continue.
	if [ "${TEMPERATURE}" = "" ]; then
		echo "*** ${ME}: WARNING: 'TEMPERATURE' not set; continuing without dark subtraction."
		return
	fi
	# Some cameras don't have a sensor temp, so don't attempt dark subtraction for them.
	[ "${TEMPERATURE}" = "n/a" ] && return

	# First check if we have an exact match.
	DARKS_DIR="${ALLSKY_DARKS}"
	DARK="${DARKS_DIR}/${TEMPERATURE}.${EXTENSION}"
	if [ -s "${DARK}" ]; then
		CLOSEST_TEMPERATURE="${TEMPERATURE}"
	else
		# Find the closest dark frame temperature wise
		typeset -i CLOSEST_TEMPERATURE	# don't set yet
		typeset -i DIFF=100		# any sufficiently high number
		typeset -i TEMPERATURE=${TEMPERATURE}
		typeset -i OVERDIFF		# DIFF when dark file temp > ${TEMPERATURE}
		typeset -i DARK_TEMPERATURE

		# Sort the files by temperature so once we find a file at a higher temperature
		# than ${TEMPERATURE}, stop, then compare it to the previous file to
		# determine which is closer to ${TEMPERATURE}.
		# Need "--general-numeric-sort" in case any files have a leading "-".
		for file in $(find "${DARKS_DIR}" -maxdepth 1 -iname "*.${EXTENSION}" | sed 's;.*/;;' | sort --general-numeric-sort)
		do
			[ "${ALLSKY_DEBUG_LEVEL}" -ge 5 ] && echo "Looking at ${file}"
			# Example file name for 21 degree dark: "21.jpg".
			if [ -s "${DARKS_DIR}/${file}" ]; then
				file=$(basename "./${file}")	# need "./" in case file has "-"
				# Get name of file (which is the temp) without extension
				DARK_TEMPERATURE=${file%.*}
				if [ ${DARK_TEMPERATURE} -gt ${TEMPERATURE} ]; then
					let OVERDIFF=${DARK_TEMPERATURE}-${TEMPERATURE}
					if [ ${OVERDIFF} -lt ${DIFF} ]; then
						CLOSEST_TEMPERATURE=${DARK_TEMPERATURE}
					fi
					break
				fi
				CLOSEST_TEMPERATURE=${DARK_TEMPERATURE}
				let DIFF=${TEMPERATURE}-${CLOSEST_TEMPERATURE}
			else
				echo "${ME}: INFORMATION: dark file '${DARKS_DIR}/${file}' is zero-length; deleting."
				rm -f "${DARKS_DIR}/${file}"
			fi
		done

		if [ "${CLOSEST_TEMPERATURE}" = "" ]; then
			echo "*** ${ME}: ERROR: No dark frame found for ${CURRENT_IMAGE} at TEMPERATURE ${TEMPERATURE}."
			echo "Either take dark frames or turn DARK_FRAME_SUBTRACTION off in config.sh"
			echo "Continuing without dark subtraction."
			return
		fi

		DARK="${DARKS_DIR}/${CLOSEST_TEMPERATURE}.${EXTENSION}"
	fi

	if [ "${ALLSKY_DEBUG_LEVEL}" -ge 4 ]; then
		echo "${ME}: Subtracting dark frame '${CLOSEST_TEMPERATURE}.${EXTENSION}' from image with TEMPERATURE=${TEMPERATURE}"
	fi
	# Update the current image - don't rename it.
	convert "${CURRENT_IMAGE}" "${DARK}" -compose minus_src -composite -type TrueColor "${CURRENT_IMAGE}"
	if [ $? -ne 0 ]; then
		# Exit since we don't know the state of ${CURRENT_IMAGE}.
		echo "*** ${ME}: ERROR: 'convert' of '${DARK}' failed"
		exit 4
	fi
fi
