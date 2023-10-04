#!/bin/bash

usage() {
  echo "Usage: $0 [-d] [-n days] repository_name"
  echo "   -d         Dry run. Show tags to be deleted without actually deleting them."
  echo "   -n days    Number of days. Tags older than these many days will be deleted."
  echo "   -h         Display this help message."
  echo "   DEBUG=true Enable debug mode."
}

check_dependencies() {
  if ! command -v jq &>/dev/null || ! command -v doctl &>/dev/null; then
    echo "Both jq and doctl should be installed to run this script."
    exit 1
  fi
}

check_for_errors() {
  local raw_response="$1"

  if [ -z "$raw_response" ]; then
    echo "No tags found for repository: $REPOSITORY. Got empty response."
    exit 0
  fi

  if jq -e '.errors' <<<"$raw_response" >/dev/null 2>&1; then
    echo "Error: $(jq -r '.errors[0].detail' <<<"$raw_response")"
    exit 1
  fi
}

DRY_RUN=false
DAYS=2

while getopts ":dh:n:" opt; do
  case $opt in
  d) DRY_RUN=true ;;
  n) DAYS=$OPTARG ;;
  h)
    usage
    exit 0
    ;;
  \?)
    echo "Invalid option: -$OPTARG" >&2
    usage
    exit 1
    ;;
  esac
done

shift $((OPTIND - 1))

if [ "$#" -lt 1 ]; then
  echo "Error: Repository name is required."
  usage
  exit 1
fi

REPOSITORY="$1"

check_dependencies

rawResponse=$(doctl registry repository list-tags "$REPOSITORY" --output=json)

[ "$DEBUG" = true ] && echo "Raw response: $rawResponse"

check_for_errors "$rawResponse"

tags=$(jq '[.[] | {updated_at, tag}]' <<<"$rawResponse")

toDelete=()

len=$(jq length <<<"$tags")
echo "Found $len tags."

for i in $(seq 0 $((len - 1))); do
  tag=$(jq -r --argjson index "$i" '.[$index].tag' <<<"$tags")
  updated=$(jq -r --argjson index "$i" '.[$index].updated_at' <<<"$tags")

  if [[ "$OSTYPE" == "darwin"* ]]; then
    updated=${updated/Z/+0000}
    updatedDate=$(date -jf "%Y-%m-%dT%H:%M:%S%z" "$updated" +%s)
  else
    updatedDate=$(date -d "$updated" +%s)
  fi

  now=$(date +%s)
  diff=$((now - updatedDate))
  diff_days=$((diff / 86400))

  if [ "$tag" != "latest" ] && [ $diff_days -ge $DAYS ]; then
    toDelete+=($tag)
  fi
done

echo "Found ${#toDelete[@]} tags to delete."

if [ "$DRY_RUN" = true ]; then
  for value in "${toDelete[@]}"; do
    echo "Would delete tag (dry run): $value"
  done
else
  for value in "${toDelete[@]}"; do
    echo "Deleting tag: $value"
    doctl registry repository delete-tag "$REPOSITORY" $value --force
  done
fi
