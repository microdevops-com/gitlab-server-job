#!/bin/bash
set -e

# Check port in SALT_MINION
if echo ${SALT_MINION} | grep -q :; then
	SALT_MINION=$(echo ${SALT_MINION} | awk -F: '{print $1}')
fi

# Run rsnapshot_backup_update_config.sh only if minion connected to this master, no error if not connected to this master
if cat alive_minions/${CI_RUNNER_DESCRIPTION}_${SALT_MINION} | grep -q 1; then
	echo One connected needed Minion found, running rsnapshot_backup_update_config.sh on this Salt Master
	sudo /srv/scripts/ci_sudo/rsnapshot_backup_update_config.sh "${SALT_MINION}"
else
	echo Skipping this Salt Master
fi
