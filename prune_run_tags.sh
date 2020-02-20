#!/bin/bash
set -e

# Check vars
if [ "_$1" = "_" -o "_$2" = "_" ]; then
	echo ERROR: needed args missing: use prune_run_tags.sh SALT_PROJECT TAGS_KEEP_AGE
	exit 1
fi
if [ "_${GL_ADMIN_PRIVATE_TOKEN}" = "_" ]; then
	echo ERROR: needed env var missing: GL_ADMIN_PRIVATE_TOKEN
	exit 1
fi
if [ "_${GL_URL}" = "_" ]; then
	echo ERROR: needed env var missing: GL_URL
	exit 1
fi

SALT_PROJECT=$1
TAGS_KEEP_AGE=$2

# Encode GitLab project name
GITLAB_PROJECT_ENCODED=$(echo "${SALT_PROJECT}" | sed -e "s#/#%2F#g")
# Get project ID
GITLAB_PROJECT_ID=$(curl -sS -H "Private-Token: ${GL_ADMIN_PRIVATE_TOKEN}" -X GET "${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ENCODED}" | jq -r ".id")

# Check GITLAB_PROJECT_ID is not null
if [ "_${GITLAB_PROJECT_ID}" = "_null" ]; then
	echo ERROR: cannot find GITLAB_PROJECT_ID - got null
	exit 1
fi

echo NOTICE: protected tags:
curl -sS -X GET -H "PRIVATE-TOKEN: ${GL_ADMIN_PRIVATE_TOKEN}" \
	"${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/protected_tags"
echo

echo NOTICE: removing protection from 'run_*' tags:
curl -sS -X DELETE -H "PRIVATE-TOKEN: ${GL_ADMIN_PRIVATE_TOKEN}" \
	"${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/protected_tags/run_*"
echo

# Temp file for headers
HEADERS_FILE=$(mktemp)

echo NOTICE: prunning old 'run_*' tags:

# Initial page
PAGE_LINK="${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/tags?pagination=keyset&per_page=50&sort=asc&search=^run_"
echo NOTICE: first page link: ${PAGE_LINK}

# Loop while link not empty
while [[ -n ${PAGE_LINK} ]]; do
	TAGS_PAGE=$(curl -sS -D ${HEADERS_FILE} -X GET -H "PRIVATE-TOKEN: ${GL_ADMIN_PRIVATE_TOKEN}" \
		-H "Content-Type: application/json" \
		${PAGE_LINK} | jq -c ".[]")

	# Take next page link from response headers
	PAGE_LINK=$(cat ${HEADERS_FILE} | grep '^Link:.*; rel="next"' | sed -r 's/^.*<(https:.+)>; rel="next".*$/\1/')
	echo NOTICE: next page link: ${PAGE_LINK}

	# Loop for tags on page
	IFS=$'\n'
	for TAGS_ROW in ${TAGS_PAGE}; do
		echo NOTICE: ---
		TAG_NAME=$(echo ${TAGS_ROW} | jq -r '.name')
		echo NOTICE: tag name: ${TAG_NAME}
		TAG_DATE=$(echo ${TAG_NAME} | sed -r 's/^run_.+([0-9]{4}-[0-9]{2}-[0-9]{2})_[0-9]{2}-[0-9]{2}-[0-9]{2}$/\1/')
		echo NOTICE: date from tag name: ${TAG_DATE}
		TAG_AGE=$(( (`date -d "00:00" +%s` - `date -d "${TAG_DATE}" +%s`) / (24*3600) ))
		echo NOTICE: tag age: ${TAG_AGE}

		# Delete tag if older than age
		if [[ ${TAG_AGE} -ge ${TAGS_KEEP_AGE} ]]; then
			echo NOTICE: tag age ${TAG_AGE} is greater or equal ${TAGS_KEEP_AGE}, deleting
			curl -sS -X DELETE -H "PRIVATE-TOKEN: ${GL_ADMIN_PRIVATE_TOKEN}" \
				"${GL_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/repository/tags/${TAG_NAME}" | jq
		fi
	done
done

# Remove temp file
rm -f ${HEADERS_FILE}
