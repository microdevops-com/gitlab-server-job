#!/bin/bash
set -e

# Check vars
if [[ "_$1" == "_" || "_$2" == "_" || "_$3" == "_" || "_$4" == "_" || "_$5" == "_" ]]; then
	echo ERROR: needed args missing: use pipeline_rsnapshot_backup.sh wait/nowait SALT_PROJECT TIMEOUT TARGET SSH/SALT SSH_HOST SSH_PORT SSH_JUMP
	echo ERROR: SSH_HOST, SSH_PORT, SSH_JUMP - optional
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

if [[ "${RSNAPSHOT_BACKUP_TYPE}" == "SSH" ]]; then
	if [[ "_$8" == "_" ]]; then
		SSH_JUMP=""
	else
		SSH_JUMP=$8
	fi
	if [[ "_$7" == "_" ]]; then
		SSH_PORT=22
	else
		SSH_PORT=$7
	fi
	if [[ "_$6" == "_" ]]; then
		SSH_HOST=${SALT_MINION}
	else
		SSH_HOST=$6
	fi
fi

# Spin marks
MARKS=( '/' '-' '\' '|' )

# Encode GitLab project name
GITLAB_PROJECT_ENCODED=$(echo "${SALT_PROJECT}" | sed -e "s#/#%2F#g")
# Get project ID
GITLAB_PROJECT_ID=$(curl -s -H "Private-Token: ${GL_USER_PRIVATE_TOKEN}" -X GET "${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ENCODED}" | jq -r ".id")

# Check GITLAB_PROJECT_ID is not null
if [[ "_${GITLAB_PROJECT_ID}" == "_null" ]]; then
	>&2 echo ERROR: cannot find GITLAB_PROJECT_ID - got null
	echo '{"target": "'${SALT_MINION}'", "pipeline_status": "null_project", "project": "'${SALT_PROJECT}'", "timeout": "'${SALT_TIMEOUT}'", "rsnapshot_backup_type": "'${RSNAPSHOT_BACKUP_TYPE}'", "ssh_host": "'${SSH_HOST}'", "ssh_port": "'${SSH_PORT}'", "ssh_jump": "'${SSH_JUMP}'"}'
	exit 1
fi

DATE_TAG=$(date "+%Y-%m-%d_%H-%M-%S")

# GitLab give 500 on manu simultaneous tag creations via API, loop with retries and random sleep between
TAG_RETRIES=0
TAG_RETRIES_MAX=10
TAG_CREATED_NAME="null"
while [[ "_${TAG_CREATED_NAME}" == "_null" ]] && (( TAG_RETRIES < TAG_RETRIES_MAX ))
do
	# Create custom git tag from master to run pipeline within
	TAG_CURL_OUT=$(curl -s -X POST -H "PRIVATE-TOKEN: ${GL_USER_PRIVATE_TOKEN}" \
		-H "Content-Type: application/json" \
		-d '{
			"tag_name": "run_rsnapshot_backup_'${SALT_MINION}'_'${DATE_TAG}'",
			"ref": "master",
			"message": "Auto-created by pipeline_rsnapshot_backup.sh"
		}' \
		"${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/tags")
	TAG_CREATED_NAME=$(echo ${TAG_CURL_OUT} | jq -r ".name")
	TAG_RETRIES=$((TAG_RETRIES+1))
	# Sleep up to 10 secs
	sleep $((RANDOM % 10))
done

# Check TAG_CREATED_NAME is not null
if [[ "_${TAG_CREATED_NAME}" == "_null" ]]; then
	>&2 echo ERROR: cannot create git tag to run within - after ${TAG_RETRIES} retries got null, raw curl out: ${TAG_CURL_OUT}
	echo '{"target": "'${SALT_MINION}'", "pipeline_status": "null_tag", "project": "'${SALT_PROJECT}'", "timeout": "'${SALT_TIMEOUT}'", "rsnapshot_backup_type": "'${RSNAPSHOT_BACKUP_TYPE}'", "ssh_host": "'${SSH_HOST}'", "ssh_port": "'${SSH_PORT}'", "ssh_jump": "'${SSH_JUMP}'"}'
	exit 1
fi

# Create pipeline
PIPELINE_ID=$(curl -s -X POST -H "PRIVATE-TOKEN: ${GL_USER_PRIVATE_TOKEN}" \
	-H "Content-Type: application/json" \
	-d "{
		\"ref\": \"${TAG_CREATED_NAME}\",
		\"variables\": [
			{\"key\": \"SALT_TIMEOUT\", \"value\": \"${SALT_TIMEOUT}\"},
			{\"key\": \"SALT_MINION\", \"value\": \"${SALT_MINION}\"},
			{\"key\": \"RSNAPSHOT_BACKUP_TYPE\", \"value\": \"${RSNAPSHOT_BACKUP_TYPE}\"},
			{\"key\": \"SSH_JUMP\", \"value\": \"${SSH_JUMP}\"},
			{\"key\": \"SSH_HOST\", \"value\": \"${SSH_HOST}\"},
			{\"key\": \"SSH_PORT\", \"value\": \"${SSH_PORT}\"}
		]
	}" \
	"${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/pipeline" | jq -r ".id")

# Check PIPELINE_ID is not null
if [[ "_${PIPELINE_ID}" == "_null" ]]; then
	>&2 echo ERROR: cannot create pipeline to run within - got null
	echo '{"target": "'${SALT_MINION}'", "pipeline_status": "null_pipeline", "project": "'${SALT_PROJECT}'", "timeout": "'${SALT_TIMEOUT}'", "rsnapshot_backup_type": "'${RSNAPSHOT_BACKUP_TYPE}'", "ssh_host": "'${SSH_HOST}'", "ssh_port": "'${SSH_PORT}'", "ssh_jump": "'${SSH_JUMP}'"}'
	exit 1
fi
# Check if pipeline id is int
if [[ ! ${PIPELINE_ID} =~ ^-?[0-9]+$ ]]; then
	>&2 echo ERROR: pipeline id ${PIPELINE_ID} is not int
	echo '{"target": "'${SALT_MINION}'", "pipeline_status": "not_int_pipeline", "project": "'${SALT_PROJECT}'", "timeout": "'${SALT_TIMEOUT}'", "rsnapshot_backup_type": "'${RSNAPSHOT_BACKUP_TYPE}'", "ssh_host": "'${SSH_HOST}'", "ssh_port": "'${SSH_PORT}'", "ssh_jump": "'${SSH_JUMP}'"}'
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
		echo -n '"ssh_jump": "'${SSH_JUMP}'"'
		echo }
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
	echo -n '"ssh_jump": "'${SSH_JUMP}'"'
	echo }
fi
