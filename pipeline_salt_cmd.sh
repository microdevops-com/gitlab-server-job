#!/bin/bash
set -e

# Check vars
if [ "_$1" = "_" -o "_$2" = "_" -o "_$3" = "_" -o "_$4" = "_" -o "_$5" = "_" ]; then
	echo ERROR: needed args missing: use pipeline_salt_cmd.sh wait/nowait SALT_PROJECT TIMEOUT TARGET CMD
	exit 1
fi
if [ "_${GL_USER_PRIVATE_TOKEN}" = "_" ]; then
	echo ERROR: needed env var missing: GL_USER_PRIVATE_TOKEN
	exit 1
fi
if [ "_${GL_URL}" = "_" ]; then
	echo ERROR: needed env var missing: GL_URL
	exit 1
fi

WAIT=$1
SALT_PROJECT=$2
SALT_TIMEOUT=$3
SALT_MINION=$4
SALT_CMD=$5

# Spin marks
MARKS=( '/' '-' '\' '|' )

# Encode GitLab project name
GITLAB_PROJECT_ENCODED=$(echo "${SALT_PROJECT}" | sed -e "s#/#%2F#g")
# Get project ID
GITLAB_PROJECT_ID=$(curl -s -H "Private-Token: ${GL_USER_PRIVATE_TOKEN}" -X GET "${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ENCODED}" | jq -r ".id")

# Check GITLAB_PROJECT_ID is not null
if [ "_${GITLAB_PROJECT_ID}" = "_null" ]; then
	>&2 echo ERROR: cannot find GITLAB_PROJECT_ID - got null
	echo '{"target": "'${SALT_MINION}'", "pipeline_status": "null_project", "project": "'${SALT_PROJECT}'", "timeout": "'${SALT_TIMEOUT}'", "cmd": "'${SALT_CMD}'"}'
	exit 1
fi

SALT_CMD_SAFE=$(echo ${SALT_CMD} | sed -r s/[^a-zA-Z0-9]+/-/g | sed -r s/^-+\|-+$//g | cut -c -80)
DATE_TAG=$(date "+%Y-%m-%d_%H-%M-%S")
SALT_CMD_BASE64=$(echo ${SALT_CMD} | base64 -w0)

# Create custom git tag from master to run pipeline within
TAG_CREATED_NAME=$(curl -s -X POST -H "PRIVATE-TOKEN: ${GL_USER_PRIVATE_TOKEN}" \
	-H "Content-Type: application/json" \
	-d '{
		"tag_name": "run_salt_cmd_'${SALT_MINION}'_'${SALT_CMD_SAFE}'_'${DATE_TAG}'",
		"ref": "master",
		"message": "Auto-created by pipeline_salt_cmd.sh"
	}' \
	"${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/tags" | jq -r ".name")

# Check TAG_CREATED_NAME is not null
if [ "_${TAG_CREATED_NAME}" = "_null" ]; then
	>&2 echo ERROR: cannot create git tag to run within - got null
	echo '{"target": "'${SALT_MINION}'", "pipeline_status": "null_tag", "project": "'${SALT_PROJECT}'", "timeout": "'${SALT_TIMEOUT}'", "cmd": "'${SALT_CMD}'"}'
	exit 1
fi

# Create pipeline
# Some quoting/globing hell happens if SALT_CMD contains space and -d '', so base64 packing-unpacking used
PIPELINE_ID=$(curl -s -X POST -H "PRIVATE-TOKEN: ${GL_USER_PRIVATE_TOKEN}" \
	-H "Content-Type: application/json" \
	-d "{
		\"ref\": \"${TAG_CREATED_NAME}\",
		\"variables\": [
			{\"key\": \"SALT_TIMEOUT\", \"value\": \"${SALT_TIMEOUT}\"},
			{\"key\": \"SALT_CMD\", \"value\": \"${SALT_CMD_BASE64}\"},
			{\"key\": \"SALT_MINION\", \"value\": \"${SALT_MINION}\"}
		]
	}" \
	"${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/pipeline" | jq -r ".id")

# Check PIPELINE_ID is not null
if [ "_${PIPELINE_ID}" = "_null" ]; then
	>&2 echo ERROR: cannot create pipeline to run within - got null
	echo '{"target": "'${SALT_MINION}'", "pipeline_status": "null_pipeline", "project": "'${SALT_PROJECT}'", "timeout": "'${SALT_TIMEOUT}'", "cmd": "'${SALT_CMD}'"}'
	exit 1
fi
# Check if pipeline id is int
if [[ ! ${PIPELINE_ID} =~ ^-?[0-9]+$ ]]; then
	>&2 echo ERROR: pipeline id ${PIPELINE_ID} is not int
	echo '{"target": "'${SALT_MINION}'", "pipeline_status": "not_int_pipeline", "project": "'${SALT_PROJECT}'", "timeout": "'${SALT_TIMEOUT}'", "cmd": "'${SALT_CMD}'"}'
	exit 1
fi

if [ "${WAIT}" = "wait" ]; then
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
		if [[ "_${PIPELINE_STATUS}" = "_success" ]]; then
			break
		fi
		# Wait on pending or running
		if [[ "_${PIPELINE_STATUS}" = "_pending" ]]; then
			continue
		fi
		if [[ "_${PIPELINE_STATUS}" = "_running" ]]; then
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
		echo -n '"cmd": "'${SALT_CMD}'"'
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
	echo -n '"cmd": "'${SALT_CMD}'"'
	echo }
fi
