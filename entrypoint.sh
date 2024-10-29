#!/bin/bash

usage() {
  echo "Usage: $0 [-d] [-n days] [-b] repository_name"
  echo "   -d         Dry run. Show tags to be deleted without actually deleting them."
  echo "   -n days    Number of days. Tags older than these many days will be deleted."
  echo "   -b         Bypass the check for the number of images within the threshold."
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

# Function to count images within the threshold
count_images_within_threshold() {
  local count=0
  local now=$(date +%s)

  for i in $(seq 0 $((len - 1))); do
    updated=$(jq -r --argjson index "$i" '.[$index].updated_at' <<<"$tags")

    if [[ "$OSTYPE" == "darwin"* ]]; then
      updated=${updated/Z/+0000}
      updatedDate=$(date -jf "%Y-%m-%dT%H:%M:%S%z" "$updated" +%s)
    else
      updatedDate=$(date -d "$updated" +%s)
    fi

    diff=$((now - updatedDate))
    diff_days=$((diff / 86400))

    if [ $diff_days -lt $DAYS ]; then
      count=$((count + 1))
    fi
  done

  echo $count
}

# Function to delete tags
delete_tags() {
  for tag in "${toDelete[@]}"; do
    if [ "$DRY_RUN" = true ]; then
      echo "Would delete tag (dry run): $tag"
    else
      echo "Deleting tag: $tag"
      if ! doctl registry repository delete-tag "$REPOSITORY" "$tag" --force; then
        echo "Failed to delete tag: $tag"
      fi
    fi
  done
}

DRY_RUN=false
DAYS=2
BYPASS_CHECK=false

while getopts ":dh:n:b" opt; do
  case $opt in
  d) DRY_RUN=true ;;
  n) DAYS=$OPTARG ;;
  b) BYPASS_CHECK=true ;;
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

# Check the number of images within the threshold
if [ "$BYPASS_CHECK" = false ]; then
  image_count_within_threshold=$(count_images_within_threshold)

  if [ "$image_count_within_threshold" -le 1 ]; then
    echo "Warning: Only $image_count_within_threshold image(s) found within the threshold of $DAYS days. Aborting deletion."
    exit 1
  fi
fi

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
    toDelete+=("$tag")
  fi
done

echo "Found ${#toDelete[@]} tags to delete."

delete_tags
