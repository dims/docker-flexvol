#!/bin/bash

# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Notes:
#  - Please install "jq" package before using this driver.
usage() {
  err "Invalid usage. Usage: "
  err "\t$0 init"
  err "\t$0 mount <mount dir> <json params>"
  err "\t$0 unmount <mount dir>"
  exit 1
}

err() {
  echo -ne $* 1>&2
}

log() {
  echo -ne $* >&1
}

ismounted() {
  MOUNT=$(findmnt -n ${MNTPATH} 2>/dev/null)
  if [ ! -z "$MOUNT" ]; then
    echo "1"
  else
    echo "0"
  fi
}


domount() {
  MNTPATH=$1
  mkdir -p ${MNTPATH} &> /dev/null

  UUID=$(uuidgen)
  VOLUME_IMAGE=$(echo $2 | jq -r '.image')
  VOLUME_NAME=$(echo $2 | jq -r '.name | select(type!="null")')

  docker pull $VOLUME_IMAGE &> /dev/null # check for image updates

  if [[ -z "${VOLUME_NAME}" ]]; then
    VOLUME_CONTAINER_ID=$(docker create --name $UUID $VOLUME_IMAGE /bin/true)
    if [[ -z "${VOLUME_CONTAINER_ID}" ]]; then
      err "{ \"status\": \"Failure\", \"message\": \"Unable to find create container from image ${VOLUME_IMAGE}\"}"
      exit 1
    fi

    pushd ${MNTPATH} &> /dev/null
    docker export $VOLUME_CONTAINER_ID | tar -xf -
    popd &>/dev/null
    docker rm -f $VOLUME_CONTAINER_ID &> /dev/null
  else
    VOLUME_CONTAINER_ID=$(docker create -v $VOLUME_NAME --name $UUID $VOLUME_IMAGE /bin/true)
    if [[ -z "${VOLUME_CONTAINER_ID}" ]]; then
      err "{ \"status\": \"Failure\", \"message\": \"Unable to find create container from image ${VOLUME_IMAGE}\"}"
      exit 1
    fi

    VOLUME_CONTAINER_DATA_PATH=$(docker inspect $VOLUME_CONTAINER_ID | jq -r '..|.Mounts?[0]|select(type!="null")|select (.Destination=="'${VOLUME_NAME}'")|.Source')
    if [[ -z "${VOLUME_CONTAINER_DATA_PATH}" ]]; then
      err "{ \"status\": \"Failure\", \"message\": \"Unable to find data path for ${VOLUME_CONTAINER_ID}\"}"
      exit 1
    fi

    mount --bind $VOLUME_CONTAINER_DATA_PATH $MNTPATH &> /dev/null
    if [ $? -ne 0 ]; then
      err "{ \"status\": \"Failure\", \"message\": \"Failed to mount ${VOLUME_CONTAINER_DATA_PATH} at ${MNTPATH}\"}"
      exit 1
    fi
  fi

  log '{"status": "Success"}'
  exit 0
}

unmount() {
  MNTPATH=$1
  if [ $(ismounted) -eq 0 ] ; then
    log '{"status": "Success"}'
    exit 0
  fi

  VOLUME_ID=$(findmnt ${MNTPATH} -cno SOURCE | sed 's/.*\[\([^]]*\)\].*/\1/g' | cut -f 6 -d '/')
  if [[ -n "${VOLUME_ID}" ]]; then
    # Hack to get the container id from the volume id (See https://github.com/moby/moby/issues/31436)
    VOLUME_CONTAINER_ID=$(docker volume rm $VOLUME_ID 2>&1 | sed 's/.*\[\([^]]*\)\].*/\1/g')
    umount ${MNTPATH} &> /dev/null
    if [ $? -ne 0 ]; then
      err "{ \"status\": \"Failed\", \"message\": \"Failed to unmount volume at ${MNTPATH}\"}"
      exit 1
    fi

    if [[ -n "${VOLUME_CONTAINER_ID}" ]]; then
      docker rm -f $VOLUME_CONTAINER_ID &> /dev/null
    fi
  else
    if [[ -n "${MNTPATH}" ]]; then
      rm -rf ${MNTPATH}/*
    fi
  fi

  log '{"status": "Success"}'
  exit 0
}

op=$1

if ! command -v jq >/dev/null 2>&1; then
  err "{ \"status\": \"Failure\", \"message\": \"'jq' binary not found. Please install jq package before using this driver\"}"
  exit 1
fi

if ! command -v uuidgen >/dev/null 2>&1; then
  err "{ \"status\": \"Failure\", \"message\": \"'uuidgen' binary not found. Please install jq package before using this driver\"}"
  exit 1
fi

if [ "$op" = "init" ]; then
  log '{"status": "Success", "capabilities": {"attach": false}}'
  exit 0
fi

if [ $# -lt 2 ]; then
  usage
fi

shift

case "$op" in
  mount)
    domount $*
    ;;
  unmount)
    unmount $*
    ;;
  *)
    log '{"status": "Not supported"}'
    exit 0
esac

exit 1
