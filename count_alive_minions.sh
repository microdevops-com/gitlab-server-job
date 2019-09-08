#!/bin/bash

mkdir alive_minions
sudo /srv/scripts/ci_sudo/count_alive_minions.sh ${SALT_MINION} > alive_minions/${CI_RUNNER_DESCRIPTION}_${SALT_MINION}
