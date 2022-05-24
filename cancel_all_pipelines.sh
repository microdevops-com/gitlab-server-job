#!/bin/bash
set -e

# Check vars
if [[ "_$1" == "_" || "_$2" == "_" ]]; then
	echo "ERROR: needed args missing: use cancel_all_pipelines.sh PROJECT STATUS_TO_CANCEL"
	exit 1
fi
if [[ "_${GL_ADMIN_PRIVATE_TOKEN}" == "_" ]]; then
	echo ERROR: needed env var missing: GL_ADMIN_PRIVATE_TOKEN
	exit 1
fi
if [[ "_${GL_URL}" == "_" ]]; then
	echo ERROR: needed env var missing: GL_URL
	exit 1
fi

PROJECT=$1
STATUS_TO_CANCEL=$2

# Temp file for headers
HEADERS_FILE=$(mktemp)

# Encode GitLab project name
GITLAB_PROJECT_ENCODED=$(echo "${PROJECT}" | sed -e "s#/#%2F#g")
# Get project ID
GITLAB_PROJECT_ID=$(curl -sS -H "Private-Token: ${GL_ADMIN_PRIVATE_TOKEN}" -X GET "${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ENCODED}" | jq -r ".id")

# Check GITLAB_PROJECT_ID is not null
if [[ "_${GITLAB_PROJECT_ID}" == "_null" ]]; then
	echo ERROR: cannot find GITLAB_PROJECT_ID - got null
	exit 1
fi

# Initial page
PAGE_LINK="${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/pipelines?pagination=keyset&per_page=50&sort=asc&status=${STATUS_TO_CANCEL}"
echo NOTICE: first page link: ${PAGE_LINK}

# Loop while link not empty
while [[ -n ${PAGE_LINK} ]]; do
	PPLNS_PAGE=$(curl -sS -D ${HEADERS_FILE} -X GET -H "PRIVATE-TOKEN: ${GL_ADMIN_PRIVATE_TOKEN}" \
		-H "Content-Type: application/json" \
		${PAGE_LINK} | jq -c ".[]")

	# Loop for pipelines on page
	IFS=$'\n'
	for PPLNS_ROW in ${PPLNS_PAGE}; do
		echo NOTICE: ---
		PPLN_ID=$(echo ${PPLNS_ROW} | jq -r '.id')
		PPLN_STATUS=$(echo ${PPLNS_ROW} | jq -r '.status')
		echo NOTICE: pipeline id: ${PPLN_ID}
		echo NOTICE: pipeline status: ${PPLN_STATUS}
		curl -sS -X POST -H "PRIVATE-TOKEN: ${GL_ADMIN_PRIVATE_TOKEN}" \
			"${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/pipelines/${PPLN_ID}/cancel"
		echo
	done
	
	# Take next page link from response headers
	PAGE_LINK=$(cat ${HEADERS_FILE} | grep -i '^Link:.*; rel="next"' | sed -r 's/^.*<(https:.+)>; rel="next".*$/\1/')
	echo NOTICE: next page link: ${PAGE_LINK}
done
