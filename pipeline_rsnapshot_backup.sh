#!/bin/bash
set -e

# Check vars
if [[ "_$1" == "_" || "_$2" == "_" || "_$3" == "_" || "_$4" == "_" || "_$5" == "_" ]]; then
	echo ERROR: needed args missing: use pipeline_rsnapshot_backup.sh wait/nowait SALT_PROJECT TIMEOUT TARGET SSH/SALT [SSH_HOST=...] [SSH_PORT=...] [SSH_JUMP=...] [SALT_SSH_IN_SALT=true]
	exit 1
fi
if [[ "_${GL_USER_PRIVATE_TOKEN}" == "_" ]]; then
	echo ERROR: needed env var missing: GL_USER_PRIVATE_TOKEN
	exit 1
fi
if [[ "_${GL_URL}" == "_" ]]; then
	echo ERROR: needed env var missing: GL_URL
	exit 1
fi

WAIT=$1
SALT_PROJECT=$2
SALT_TIMEOUT=$3 # meaningful only for SALT type
SALT_MINION=$4
RSNAPSHOT_BACKUP_TYPE=$5

# Find optional args
for ARGUMENT in "$@"
do
	KEY=$(echo ${ARGUMENT} | cut -f1 -d=)
	VALUE=$(echo ${ARGUMENT} | cut -f2 -d=)
	case "$KEY" in
		SSH_HOST) SSH_HOST=${VALUE} ;;
		SSH_PORT) SSH_PORT=${VALUE} ;;
		SSH_JUMP) SSH_JUMP=${VALUE} ;;
		SALT_SSH_IN_SALT) SALT_SSH_IN_SALT=${VALUE} ;;
		*) ;;
	esac
done

if [[ "${RSNAPSHOT_BACKUP_TYPE}" == "SSH" ]]; then
	if [[ "_${SSH_PORT}" == "_" ]]; then
		SSH_PORT=22
	fi
	if [[ "_${SSH_HOST}" == "_" ]]; then
		SSH_HOST=${SALT_MINION}
	fi
fi

# Spin marks
MARKS=( '/' '-' '\' '|' )

# Save pipeline history if needed envs set
function save_pipeline_history () {
	if [[ -n "${PG_DB_USER}" && -n "${PG_DB_PASS}" && -n "${PG_DB_NAME}" && -n "${PG_DB_HOST}" && -n "${PG_DB_PORT}" ]]; then
		if [[ -x $(which psql) ]]; then
			echo "
				INSERT INTO
					pipeline_rsnapshot_backup_history (target, pipeline_id, pipeline_url, pipeline_status, project, timeout, rsnapshot_backup_type, ssh_host, ssh_port, ssh_jump)
				VALUES
					(
						'"${SALT_MINION}"',
						'"${PIPELINE_ID}"',
						'"${GL_URL}/${SALT_PROJECT}/pipelines/${PIPELINE_ID}"',
						'"${PIPELINE_STATUS}"',
						'"${SALT_PROJECT}"',
						'"${SALT_TIMEOUT}"',
						'"${RSNAPSHOT_BACKUP_TYPE}"',
						'"${SSH_HOST}"',
						'"${SSH_PORT}"',
						'"${SSH_JUMP}"'
					)
				;" | PGPASSWORD="${PG_DB_PASS}" psql -h "${PG_DB_HOST}" -p "${PG_DB_PORT}" -U "${PG_DB_USER}" -w -q "${PG_DB_NAME}"
		else
			>&2 echo WARNING: psql not found - cannot save pipeline history
		fi
	else
			>&2 echo WARNING: PG_DB_HOST, PG_DB_NAME, PG_DB_PASS, PG_DB_USER are not set - cannot save pipeline history
	fi
}

# Encode GitLab project name
GITLAB_PROJECT_ENCODED=$(echo "${SALT_PROJECT}" | sed -e "s#/#%2F#g")
# Get project ID
if ! GITLAB_PROJECT_ID=$(curl -s -H "Private-Token: ${GL_USER_PRIVATE_TOKEN}" -X GET "${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ENCODED}" | jq -r ".id"); then
	>&2 echo ERROR: cannot find GITLAB_PROJECT_ID - curl error
	PIPELINE_STATUS="null_project"
	echo '{"target": "'${SALT_MINION}'", "pipeline_status": "'${PIPELINE_STATUS}'", "project": "'${SALT_PROJECT}'", "timeout": "'${SALT_TIMEOUT}'", "rsnapshot_backup_type": "'${RSNAPSHOT_BACKUP_TYPE}'", "ssh_host": "'${SSH_HOST}'", "ssh_port": "'${SSH_PORT}'", "ssh_jump": "'${SSH_JUMP}'", "salt_ssh_in_salt": "'${SALT_SSH_IN_SALT}'"}'
	save_pipeline_history
	exit 1
fi

# Check GITLAB_PROJECT_ID is not null
if [[ "_${GITLAB_PROJECT_ID}" == "_null" ]]; then
	>&2 echo ERROR: cannot find GITLAB_PROJECT_ID - got null
	PIPELINE_STATUS="null_project"
	echo '{"target": "'${SALT_MINION}'", "pipeline_status": "'${PIPELINE_STATUS}'", "project": "'${SALT_PROJECT}'", "timeout": "'${SALT_TIMEOUT}'", "rsnapshot_backup_type": "'${RSNAPSHOT_BACKUP_TYPE}'", "ssh_host": "'${SSH_HOST}'", "ssh_port": "'${SSH_PORT}'", "ssh_jump": "'${SSH_JUMP}'", "salt_ssh_in_salt": "'${SALT_SSH_IN_SALT}'"}'
	save_pipeline_history
	exit 1
fi

# Create pipeline
PIPELINE_ID=$(curl -s -X POST -H "PRIVATE-TOKEN: ${GL_USER_PRIVATE_TOKEN}" \
	-H "Content-Type: application/json" \
	-d "{
		\"ref\": \"master\",
		\"variables\": [
			{\"key\": \"SALT_TIMEOUT\", \"value\": \"${SALT_TIMEOUT}\"},
			{\"key\": \"SALT_MINION\", \"value\": \"${SALT_MINION}\"},
			{\"key\": \"RSNAPSHOT_BACKUP_TYPE\", \"value\": \"${RSNAPSHOT_BACKUP_TYPE}\"},
			{\"key\": \"SSH_JUMP\", \"value\": \"${SSH_JUMP}\"},
			{\"key\": \"SSH_HOST\", \"value\": \"${SSH_HOST}\"},
			{\"key\": \"SSH_PORT\", \"value\": \"${SSH_PORT}\"},
			{\"key\": \"SALT_SSH_IN_SALT\", \"value\": \"${SALT_SSH_IN_SALT}\"}
		]
	}" \
	"${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/pipeline" | jq -r ".id")

# Check PIPELINE_ID is not null
if [[ "_${PIPELINE_ID}" == "_null" ]]; then
	>&2 echo ERROR: cannot create pipeline to run within - got null
	PIPELINE_STATUS="null_pipeline"
	echo '{"target": "'${SALT_MINION}'", "pipeline_status": "'${PIPELINE_STATUS}'", "project": "'${SALT_PROJECT}'", "timeout": "'${SALT_TIMEOUT}'", "rsnapshot_backup_type": "'${RSNAPSHOT_BACKUP_TYPE}'", "ssh_host": "'${SSH_HOST}'", "ssh_port": "'${SSH_PORT}'", "ssh_jump": "'${SSH_JUMP}'", "salt_ssh_in_salt": "'${SALT_SSH_IN_SALT}'"}'
	save_pipeline_history
	exit 1
fi
# Check if pipeline id is int
if [[ ! ${PIPELINE_ID} =~ ^-?[0-9]+$ ]]; then
	>&2 echo ERROR: pipeline id ${PIPELINE_ID} is not int
	PIPELINE_STATUS="not_int_pipeline"
	echo '{"target": "'${SALT_MINION}'", "pipeline_status": "'${PIPELINE_STATUS}'", "project": "'${SALT_PROJECT}'", "timeout": "'${SALT_TIMEOUT}'", "rsnapshot_backup_type": "'${RSNAPSHOT_BACKUP_TYPE}'", "ssh_host": "'${SSH_HOST}'", "ssh_port": "'${SSH_PORT}'", "ssh_jump": "'${SSH_JUMP}'", "salt_ssh_in_salt": "'${SALT_SSH_IN_SALT}'"}'
	save_pipeline_history
	exit 1
fi

if [[ "${WAIT}" == "wait" ]]; then
	i=1
	# Get pipeline status
	while true; do
		sleep 2
		CURL_OUT=$(curl -s -H "PRIVATE-TOKEN: ${GL_USER_PRIVATE_TOKEN}" ${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/pipelines/${PIPELINE_ID})
		# Debug output
		#echo Curl Pipeline Status:
		#echo ${CURL_OUT}
		# Get status of pipeline
		PIPELINE_STATUS=$(echo ${CURL_OUT} | jq -r ".status")
		>&2 printf '%s\r' "${MARKS[i++ % ${#MARKS[@]}]}"
		>&2 echo -n "${PIPELINE_STATUS}"
		# Exit with OK on success
		if [[ "_${PIPELINE_STATUS}" == "_success" ]]; then
			break
		fi
		# Wait on pending or running
		if [[ "_${PIPELINE_STATUS}" == "_pending" ]]; then
			continue
		fi
		if [[ "_${PIPELINE_STATUS}" == "_running" ]]; then
			continue
		fi
		if [[ "_${PIPELINE_STATUS}" == "_created" ]]; then
			continue
		fi
		# All other statuses or anything else - error
		>&2 echo -en "\r"
		>&2 echo ERROR: status ${PIPELINE_STATUS} is failed or unknown to wait any longer
		echo -n {
		echo -n '"target": "'${SALT_MINION}'", '
		echo -n '"pipeline_id": "'${PIPELINE_ID}'", '
		echo -n '"pipeline_url": "'${GL_URL}/${SALT_PROJECT}/pipelines/${PIPELINE_ID}'", '
		echo -n '"pipeline_status": "'${PIPELINE_STATUS}'", '
		echo -n '"project": "'${SALT_PROJECT}'", '
		echo -n '"timeout": "'${SALT_TIMEOUT}'", '
		echo -n '"rsnapshot_backup_type": "'${RSNAPSHOT_BACKUP_TYPE}'", '
		echo -n '"ssh_host": "'${SSH_HOST}'", '
		echo -n '"ssh_port": "'${SSH_PORT}'", '
		echo -n '"ssh_jump": "'${SSH_JUMP}'", '
		echo -n '"salt_ssh_in_salt": "'${SALT_SSH_IN_SALT}'"'
		echo }
		save_pipeline_history
		exit 1
	done
	echo -en "\r"
	echo -n {
	echo -n '"target": "'${SALT_MINION}'", '
	echo -n '"pipeline_id": "'${PIPELINE_ID}'", '
	echo -n '"pipeline_url": "'${GL_URL}/${SALT_PROJECT}/pipelines/${PIPELINE_ID}'", '
	echo -n '"pipeline_status": "'${PIPELINE_STATUS}'", '
	echo -n '"project": "'${SALT_PROJECT}'", '
	echo -n '"timeout": "'${SALT_TIMEOUT}'", '
	echo -n '"rsnapshot_backup_type": "'${RSNAPSHOT_BACKUP_TYPE}'", '
	echo -n '"ssh_host": "'${SSH_HOST}'", '
	echo -n '"ssh_port": "'${SSH_PORT}'", '
	echo -n '"ssh_jump": "'${SSH_JUMP}'", '
	echo -n '"salt_ssh_in_salt": "'${SALT_SSH_IN_SALT}'"'
	echo }
	save_pipeline_history
else
	PIPELINE_STATUS="nowait"
	save_pipeline_history
fi
