#!/bin/sh
HOST="$1"
ENV="$2"
#PASSWD="$3"
mkdir -p /tmp/user_creation
/usr/bin/curl -s  -u admin:admin "http://$HOST:4502/bin/security/authorizables.json?ml=0&_charset_=utf-8&filter=&hideUsers=true&hideGroups=false" | jq --raw-output  '.authorizables[] .id' | grep -vE "^administrators|analytics-administrators|community-administrators|community-enablementmanagers|community-groupadmin|community-members|community-moderators|community-sitecontentmanager|content-authors|contributor|dam-users|fd-administrators|forms-submission-reviewers|forms-users|mp-contributors|mp-designers|mp-editors|mp-users|operators|order-administrators|projects-administrators|projects-users|tag-administrators|target-activity-authors|target-administrators|template-authors|user-administrators|workflow-administrators|workflow-editors|workflow-users" > /tmp/user_creation/user_creation_job_${ENV}_groups.txt

