#!/bin/bash

# Check port in SALT_MINION
if echo ${SALT_MINION} | grep -q :; then
	SALT_MINION=$(echo ${SALT_MINION} | awk -F: '{print $1}')
fi

mkdir alive_minions
sudo /srv/scripts/ci_sudo/count_alive_minions.sh ${SALT_MINION} > alive_minions/${CI_RUNNER_DESCRIPTION}_${SALT_MINION}
