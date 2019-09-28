#!/bin/bash
set -e

# Run rsnapshot_backup_update_config.sh only if minion connected to this master, no error if not connected to this master
if cat alive_minions/${CI_RUNNER_DESCRIPTION}_${SERVER_FQDN} | grep -q 1; then
	echo One connected needed Minion found, running rsnapshot_backup_update_config.sh on this Salt Master
	sudo /srv/scripts/ci_sudo/rsnapshot_backup_update_config.sh "${SERVER_FQDN}"
else
	echo Skipping this Salt Master
fi
