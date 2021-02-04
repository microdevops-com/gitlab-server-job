#!/bin/bash
set -e

# Run send_notify_devilry.sh only if minion connected to this master, no error if not connected to this master
if cat alive_minions/${CI_RUNNER_DESCRIPTION}_${SALT_MINION} | grep -q 1; then
	echo One connected needed Minion found, running send_notify_devilry.sh on this Salt Master
	sudo --preserve-env /srv/scripts/ci_sudo/send_notify_devilry.sh
else
	echo Skipping this Salt Master
fi
