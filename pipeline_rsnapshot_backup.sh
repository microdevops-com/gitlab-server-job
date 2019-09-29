#!/bin/bash
set -e

# Check vars
if [ "_$1" = "_" -o "_$2" = "_" -o "_$3" = "_" -o "_$4" = "_" -o "_$5" = "_" ]; then
	echo ERROR: needed args missing: use pipeline_rsnapshot_backup.sh wait/nowait SALT_PROJECT TIMEOUT TARGET SSH/SALT
	exit 1
fi
if [ "_${GL_USER_PRIVATE_TOKEN}" = "_" -o "_${GL_URL}" = "_" ]; then
	echo ERROR: needed env var missing: GL_USER_PRIVATE_TOKEN
	exit 1
fi

WAIT=$1
SALT_PROJECT=$2
SALT_TIMEOUT=$3 # meaningful only for SALT type
SALT_MINION=$4
RSNAPSHOT_BACKUP_TYPE=$5

# Encode GitLab project name
GITLAB_PROJECT_ENCODED=$(echo "${SALT_PROJECT}" | sed -e "s#/#%2F#g")
# Get project ID
GITLAB_PROJECT_ID=$(curl -s -H "Private-Token: ${GL_USER_PRIVATE_TOKEN}" -X GET "${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ENCODED}" | jq -r ".id")

# Check GITLAB_PROJECT_ID is not null
if [ "_${GITLAB_PROJECT_ID}" = "_null" ]; then
	echo ERROR: cannot find GITLAB_PROJECT_ID - got null
	exit 1
fi

DATE_TAG=$(date "+%Y-%m-%d_%H-%M-%S")

# Create custom git tag from master to run pipeline within
TAG_CREATED_NAME=$(curl -s -X POST -H "PRIVATE-TOKEN: ${GL_USER_PRIVATE_TOKEN}" \
	-H "Content-Type: application/json" \
	-d '{
		"tag_name": "run_rsnapshot_backup_'${SALT_MINION}'_'${DATE_TAG}'",
		"ref": "master",
		"message": "Auto-created by pipeline_rsnapshot_backup.sh"
	}' \
	"${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/tags" | jq -r ".name")

# Check TAG_CREATED_NAME is not null
if [ "_${TAG_CREATED_NAME}" = "_null" ]; then
	echo ERROR: cannot create git tag to run within - got null
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
			{\"key\": \"RSNAPSHOT_BACKUP_TYPE\", \"value\": \"${RSNAPSHOT_BACKUP_TYPE}\"}
		]
	}" \
	"${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/pipeline" | jq -r ".id")

echo NOTICE: Pipeline ID: ${PIPELINE_ID}
echo NOTICE: Pipeline URL: ${GL_URL}/${SALT_PROJECT}/pipelines/${PIPELINE_ID}
# Check PIPELINE_ID is not null
if [ "_${PIPELINE_ID}" = "_null" ]; then
	echo ERROR: cannot create pipeline to run within - got null
	exit 1
fi
# Check if pipeline id is int
if [[ ! ${PIPELINE_ID} =~ ^-?[0-9]+$ ]]; then
	echo ERROR: pipeline id is not int
	exit 1
fi

if [ "${WAIT}" = "wait" ]; then
	# Get pipeline status
	while true; do
		sleep 2
		CURL_OUT=$(curl -s -H "PRIVATE-TOKEN: ${GL_USER_PRIVATE_TOKEN}" ${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/pipelines/${PIPELINE_ID})
		# Debug output
		#echo Curl Pipeline Status:
		#echo ${CURL_OUT}
		# Get status of pipeline
		PIPELINE_STATUS=$(echo ${CURL_OUT} | jq -r ".status")
		echo NOTICE: Pipeline Status: ${PIPELINE_STATUS}
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
		echo ERROR: status ${PIPELINE_STATUS} is failed or unknown to wait any longer
		exit 1
	done
	echo "NOTICE: Pipeline ID ${PIPELINE_ID} successfully finished"
fi
