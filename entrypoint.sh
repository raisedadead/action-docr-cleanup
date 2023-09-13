#!/bin/bash

# Function to display help/usage
function usage() {
  echo "Usage: $0 [-d] [-n days] repository_name"
  echo "   -d         Dry run. Show tags to be deleted without actually deleting them."
  echo "   -n days    Number of days. Tags older than these many days will be deleted."
  echo "   -h         Display this help message."
}

# Check if jq and doctl are installed
if ! command -v jq &>/dev/null || ! command -v doctl &>/dev/null; then
  echo "Both jq and doctl should be installed to run this script."
  exit 1
fi

# Initialize dry run flag as false and days as 2 (default)
DRY_RUN=false
DAYS=2

# Parse command line options
while getopts ":dh:n:" opt; do
  case $opt in
  d)
    DRY_RUN=true
    ;;
  n)
    DAYS=$OPTARG
    ;;
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

# Shift out the options to get positional parameters
shift $((OPTIND - 1))

# Check for repository argument
if [ "$#" -ne 1 ]; then
  echo "Repository name is required."
  usage
  exit 1
fi

REPOSITORY="$1"

# Get the list of tags from the specified DigitalOcean container registry
rawResponse=$(doctl registry repository list-tags "$REPOSITORY" --output=json)

# Extract the 'updated_at' and 'tag' fields from the raw response using jq
tags=$(jq '[.[] | {updated_at, tag}]' <<<"$rawResponse")

# Initialize an empty array to store tags that need to be deleted
toDelete=()

# Determine the total number of tags
len=$(jq length <<<"$tags")
echo "Found $len tags."

# Iterate over each tag to check its age
for i in $(seq 0 $((len - 1))); do
  # Extract the tag name and its last updated timestamp
  tag=$(jq -r --argjson index "$i" '.[$index].tag' <<<"$tags")
  updated=$(jq -r --argjson index "$i" '.[$index].updated_at' <<<"$tags")

  # Convert the updated date to seconds since the epoch
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # For macOS, replace the 'Z' with '+0000' to signify UTC
    updated=${updated/Z/+0000}
    updatedDate=$(date -jf "%Y-%m-%dT%H:%M:%S%z" "$updated" +%s)
  else
    # For Linux
    updatedDate=$(date -d "$updated" +%s)
  fi

  # Get the current time in seconds since the epoch
  now=$(date +%s)

  # Calculate the difference in time between the current time and the tag's last update
  diff=$((now - updatedDate))

  # Calculate the time difference in days
  diff_days=$((diff / 86400))

  # If the tag isn't "latest" and it's older than the specified days, add it to the deletion list
  if [ "$tag" != "latest" ] && [ $diff_days -ge $DAYS ]; then
    toDelete+=($tag)
  fi
done

# Display the number of tags marked for deletion
echo "Found ${#toDelete[@]} tags to delete."

# If dry run is enabled, just display the tags to be deleted
if [ "$DRY_RUN" = true ]; then
  for value in "${toDelete[@]}"; do
    echo "Would delete tag (dry run): $value"
  done
else
  # Iterate over the deletion list and delete each tag from the repository
  for value in "${toDelete[@]}"; do
    echo "Deleting tag: $value"
    doctl registry repository delete-tag "$REPOSITORY" $value --force
  done
fi
