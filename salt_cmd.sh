#!/bin/bash
set -e

# Check port in SALT_MINION
if echo ${SALT_MINION} | grep -q :; then
	SALT_MINION=$(echo ${SALT_MINION} | awk -F: '{print $1}')
fi

# Run salt_cmd.sh only if minion connected to this master, no error if not connected to this master
if cat alive_minions/${CI_RUNNER_DESCRIPTION}_${SALT_MINION} | grep -q 1; then
	echo One connected needed Minion found, running salt_cmd.sh on this Salt Master
	sudo /srv/scripts/ci_sudo/salt_cmd.sh "${SALT_TIMEOUT}" "${SALT_MINION}" "${SALT_CMD}"
else
	echo Skipping this Salt Master
fi
