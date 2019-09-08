#!/bin/bash
set -e

# Run salt_cmd.sh only if minion connected to this master, no error if not connected to this master
if cat alive_minions/${CI_RUNNER_DESCRIPTION}_${SALT_MINION} | grep -q 1; then
	echo One connected needed Minion found, running salt_cmd.sh on this Salt Master
	sudo /srv/scripts/ci_sudo/salt_cmd.sh "${SALT_TIMEOUT}" "${SALT_MINION}" "${SALT_CMD}"
else
	echo Skipping this Salt Master
fi
