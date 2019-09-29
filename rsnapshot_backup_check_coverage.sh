#!/bin/bash
set -e

# Run rsnapshot_backup_check_coverage.sh only if minion connected to this master, no error if not connected to this master
if cat alive_minions/${CI_RUNNER_DESCRIPTION}_${SALT_MINION} | grep -q 1; then
	echo One connected needed Minion found, running rsnapshot_backup_check_coverage.sh on this Salt Master
	sudo /srv/scripts/ci_sudo/rsnapshot_backup_check_coverage.sh "${SALT_MINION}"
else
	echo Skipping this Salt Master
fi
