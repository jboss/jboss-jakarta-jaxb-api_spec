#!/bin/bash -ex
#
# Copyright (c) 2019 Oracle and/or its affiliates. All rights reserved.
#
# This program and the accompanying materials are made available under the
# terms of the Eclipse Distribution License v. 1.0, which is available at
# http://www.eclipse.org/org/documents/edl-v10.php.
#
# SPDX-License-Identifier: BSD-3-Clause

#
# Arguments:
#  $1 - SPEC_VERSION
#  $2 - NEXT_SPEC_VERSION
#  $3 - API_VERSION
#  $4 - NEXT_API_VERSION
#  $5 - DRY_RUN
#  $6 - OVERWRITE

SPEC_VERSION="${1}"
NEXT_SPEC_VERSION="${2}"
API_VERSION="${3}"
NEXT_API_VERSION="${4}"
DRY_RUN="${5}"
OVERWRITE="${6}"

. etc/scripts/maven.incl.sh
. etc/scripts/nexus.incl.sh

read_version 'SPEC' "${SPEC_DIR}"
read_version 'API' "${API_DIR}"

if [ -z "${API_RELEASE_VERSION}" ]; then
  echo '-[ Missing required API release version number! ]-------------------------------'
  exit 1
fi
if [ -z "${SPEC_RELEASE_VERSION}" ]; then
  echo '-[ Missing required specification release version number! ]---------------------'
  exit 1
fi

RELEASE_TAG="SPEC-${SPEC_RELEASE_VERSION}_API-${API_RELEASE_VERSION}"
RELEASE_BRANCH="SPEC-${SPEC_RELEASE_VERSION}_API-${API_RELEASE_VERSION}_RELEASE"

if [ ${DRY_RUN} = 'true' ]; then
  echo '-[ Dry run turned on ]----------------------------------------------------------'
  MVN_DEPLOY_ARGS='install'
  echo '-[ Skipping GitHub branch and tag checks ]--------------------------------------'
else
  MVN_DEPLOY_ARGS='deploy'
  GIT_ORIGIN=`git remote`
  echo '-[ Prepare branch ]-------------------------------------------------------------'
  if [[ -n `git branch -r | grep "${GIT_ORIGIN}/${RELEASE_BRANCH}"` ]]; then
    if [ "${OVERWRITE}" = 'true' ]; then
      echo "${GIT_ORIGIN}/${RELEASE_BRANCH} branch already exists, deleting"
      git push --delete origin "${RELEASE_BRANCH}" && true
    else
      echo "Error: ${GIT_ORIGIN}/${RELEASE_BRANCH} branch already exists"
      exit 1
    fi
  fi
  echo '-[ Release tag cleanup ]--------------------------------------------------------'
  if [[ -n `git ls-remote --tags ${GIT_ORIGIN} | grep "${RELEASE_TAG}"` ]]; then
    if [ "${OVERWRITE}" = 'true' ]; then
      echo "${RELEASE_TAG} tag already exists, deleting"
      git push --delete origin "${RELEASE_TAG}" && true
    else
      echo "Error: ${RELEASE_TAG} tag already exists"
      exit 1
    fi
  fi
fi

# Always delete local branch if exists
git branch --delete "${RELEASE_BRANCH}" && true
git checkout -b ${RELEASE_BRANCH}

# Always delete local tag if exists
git tag --delete "${RELEASE_TAG}" && true

# Read Maven identifiers
read_mvn_id 'SPEC' "${SPEC_DIR}"
read_mvn_id 'API' "${API_DIR}/jaxb-api"

# Set Nexus identifiers
SPEC_STAGING_DESC="${SPEC_GROUP_ID}:${SPEC_ARTIFACT_ID}:${SPEC_RELEASE_VERSION}"
SPEC_STAGING_KEY=$(echo ${SPEC_STAGING_DESC} | sed -e 's/\./\\\./g')
API_STAGING_DESC="${API_GROUP_ID}:${API_ARTIFACT_ID}:${API_RELEASE_VERSION}"
API_STAGING_KEY=$(echo ${API_STAGING_DESC} | sed -e 's/\./\\\./g')

# Set release versions
echo '-[ SPEC release version ]-------------------------------------------------------'
set_version 'SPEC' "${SPEC_DIR}" "${SPEC_RELEASE_VERSION}" "${SPEC_GROUP_ID}" "${SPEC_ARTIFACT_ID}" ''
echo '-[ API release version ]--------------------------------------------------------'
set_version 'API' "${API_DIR}" "${API_RELEASE_VERSION}" "${API_GROUP_ID}" "${API_ARTIFACT_ID}" ''

drop_artifacts "${SPEC_STAGING_KEY}" "${SPEC_DIR}"
drop_artifacts "${API_STAGING_KEY}" "${API_DIR}"

echo '-[ Deploy artifacts to staging repository ]-----------------------------'
# Verify, sign and deploy release
(cd ${SPEC_DIR} && \
  mvn -U -C \
      -Poss-release,staging -DskipTests \
      -Dstatus='Final Release' \
      -DstagingDescription="${SPEC_STAGING_DESC}" \
      clean ${MVN_DEPLOY_ARGS})
(cd ${API_DIR} && \
  mvn -U -C \
      -Poss-release,staging -DskipTests \
      -DstagingDescription="${API_STAGING_DESC}" \
      clean ${MVN_DEPLOY_ARGS})

echo '-[ Tag release ]----------------------------------------------------------------'
git tag "${RELEASE_TAG}" -m "JSON-B Specification and API release"

# Set next release cycle snapshot version
echo '-[ SPEC next snapshot version ]-------------------------------------------------'
set_version 'SPEC' "${SPEC_DIR}" "${SPEC_NEXT_SNAPSHOT}" "${SPEC_GROUP_ID}" "${SPEC_ARTIFACT_ID}" ''
echo '-[ API next snapshot version ]--------------------------------------------------'
set_version 'API' "${API_DIR}" "${API_NEXT_SNAPSHOT}" "${API_GROUP_ID}" "${API_ARTIFACT_ID}" ''

if [ ${DRY_RUN} = 'true' ]; then
  echo '-[ Skipping GitHub update ]-----------------------------------------------------'
else
  echo '-[ Push branch and tag to GitHub ]----------------------------------------------'
  git push origin "${RELEASE_BRANCH}"
  git push origin "${RELEASE_TAG}"
fi
