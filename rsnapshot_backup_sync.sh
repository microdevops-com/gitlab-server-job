#!/bin/bash
set -e

# Run rsnapshot_backup_sync.sh only if minion connected to this master, no error if not connected to this master
if cat alive_minions/${CI_RUNNER_DESCRIPTION}_${SALT_MINION} | grep -q 1; then
	echo One connected needed Minion found, running rsnapshot_backup_sync.sh on this Salt Master
	if sudo /srv/scripts/ci_sudo/rsnapshot_backup_sync.sh "${SALT_TIMEOUT}" "${SALT_MINION}" "${RSNAPSHOT_BACKUP_TYPE}" "${SSH_HOST}" "${SSH_PORT}" "${SSH_JUMP}"; then
		echo "export RSNAPSHOT_BACKUP_SYNC=success" > rsnapshot_backup_sync_status
	else
		echo "export RSNAPSHOT_BACKUP_SYNC=failed" > rsnapshot_backup_sync_status
		exit 1
	fi
else
	echo Skipping this Salt Master
	rm -f rsnapshot_backup_sync_status # Remove this artifact if exist and not needed
fi
