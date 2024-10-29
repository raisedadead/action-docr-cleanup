#!/bin/bash

usage() {
  echo "Usage: $0 [-d] [-n days] [-b] [--keep-last count] repository_name"
  echo "   -d              Dry run. Show tags to be deleted without actually deleting them."
  echo "   -n days         Number of days. Tags older than these many days will be deleted."
  echo "   -b              Bypass the check for the number of images within the threshold."
  echo "   --keep-last n   Keep the n most recent images, regardless of age."
  echo "   -h              Display this help message."
  echo "   DEBUG=true      Enable debug mode."
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
  local count=0
  for tag in "${toDelete[@]}"; do
    if [ -n "$MAX_DELETE" ] && [ $count -ge "$MAX_DELETE" ]; then
      echo "Reached maximum deletion count of $MAX_DELETE"
      break
    fi

    if [ "$DRY_RUN" = true ]; then
      echo "Would delete tag (dry run): $tag"
    else
      echo "Deleting tag: $tag"
      if ! doctl registry repository delete-tag "$REPOSITORY" "$tag" --force; then
        echo "Failed to delete tag: $tag"
      fi
    fi
    count=$((count + 1))
  done

  if [ -n "$MAX_DELETE" ]; then
    echo "Deleted/Would delete $count out of maximum $MAX_DELETE requested tags"
  fi
}

DRY_RUN=false
DAYS=2
BYPASS_CHECK=false
KEEP_LAST=""

# Modified to handle long options
while [[ $# -gt 0 ]]; do
  case $1 in
  -d)
    DRY_RUN=true
    shift
    ;;
  -n)
    DAYS="$2"
    shift 2
    ;;
  -b)
    BYPASS_CHECK=true
    shift
    ;;
  --keep-last)
    KEEP_LAST="$2"
    shift 2
    ;;
  -h)
    usage
    exit 0
    ;;
  -*)
    echo "Invalid option: $1" >&2
    usage
    exit 1
    ;;
  *)
    REPOSITORY="$1"
    shift
    ;;
  esac
done

if [ -z "$REPOSITORY" ]; then
  echo "Error: Repository name is required."
  usage
  exit 1
fi

check_dependencies

rawResponse=$(doctl registry repository list-tags "$REPOSITORY" --output=json)

[ "$DEBUG" = true ] && echo "Raw response: $rawResponse"

check_for_errors "$rawResponse"

# Get all non-latest tags immediately
tags=$(jq '[.[] | select(.tag != "latest") | {updated_at, tag}]' <<<"$rawResponse")

toDelete=()

len=$(jq length <<<"$tags")
echo "Repository: $REPOSITORY"
echo "Total tags found: $len (excluding 'latest')"
echo "Parameters:"
echo "  • Days threshold: $DAYS"
if [ -n "$KEEP_LAST" ]; then
  echo "  • Keep last: $KEEP_LAST"
fi
echo "  • Dry run: $DRY_RUN"
echo "  • Safety check: $([ "$BYPASS_CHECK" = true ] && echo "bypassed" || echo "enabled")"
echo ""

# Check the number of images within the threshold
if [ "$BYPASS_CHECK" = false ]; then
  image_count_within_threshold=$(count_images_within_threshold)

  if [ "$image_count_within_threshold" -le 1 ]; then
    echo "WARNING: Safety check failed"
    echo "  • No images found newer than $DAYS day(s)"
    exit 1
  fi
fi

# Sort tags by date (newest first) and apply keep-last logic
if [ -n "$KEEP_LAST" ]; then
  # Convert to integer and validate
  if ! [[ "$KEEP_LAST" =~ ^[0-9]+$ ]]; then
    echo "Error: --keep-last value must be a positive integer"
    exit 1
  fi

  # Create a temporary array of all tags with timestamps
  sorted_tags=()

  for i in $(seq 0 $((len - 1))); do
    tag=$(jq -r --argjson index "$i" '.[$index].tag' <<<"$tags")
    updated=$(jq -r --argjson index "$i" '.[$index].updated_at' <<<"$tags")

    # Convert date to timestamp for reliable sorting
    if [[ "$OSTYPE" == "darwin"* ]]; then
      updated=${updated/Z/+0000}
      timestamp=$(date -jf "%Y-%m-%dT%H:%M:%S%z" "$updated" +%s)
    else
      timestamp=$(date -d "$updated" +%s)
    fi

    # Store timestamp and tag together
    sorted_tags+=("$timestamp:$tag")
  done

  # Sort timestamps in descending order
  IFS=$'\n' sorted_tags=($(sort -t: -k1,1nr <<<"${sorted_tags[*]}"))
  unset IFS

  echo "Operation:"
  echo "  • Strategy: Keep $KEEP_LAST most recent tags"
  echo "  • Total tags found: ${#sorted_tags[@]}"

  # Debug: Show which tags we're keeping
  if [ "$DEBUG" = true ]; then
    echo "  • Tags to keep:"
    for i in $(seq 0 $((KEEP_LAST - 1))); do
      if [ "$i" -lt "${#sorted_tags[@]}" ]; then
        tag="${sorted_tags[$i]#*:}"
        echo "    - $tag"
      fi
    done
  fi

  # Process tags for deletion
  toDelete=()
  for i in "${!sorted_tags[@]}"; do
    timestamp="${sorted_tags[$i]%%:*}"
    tag="${sorted_tags[$i]#*:}"

    # Skip the most recent KEEP_LAST tags
    if [ "$i" -lt "$KEEP_LAST" ]; then
      continue
    fi

    # For remaining tags, check if they're old enough to delete
    now=$(date +%s)
    diff=$((now - timestamp))
    diff_days=$((diff / 86400))

    if [ $diff_days -ge $DAYS ]; then
      toDelete+=("$tag")
    fi
  done
else
  echo "Operation:"
  echo "  • Strategy: Remove tags older than $DAYS days"
  # Original logic for when --keep-last is not specified
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

    if [ $diff_days -ge $DAYS ]; then
      toDelete+=("$tag")
    fi
  done
fi

if [ ${#toDelete[@]} -eq 0 ]; then
  echo "Result: No tags to delete"
else
  echo "Result: Found ${#toDelete[@]} tag(s) to delete"
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY RUN - No changes will be made]"
    for tag in "${toDelete[@]}"; do
      echo "  • Would delete: $tag"
    done
  else
    for tag in "${toDelete[@]}"; do
      echo "  • Deleting: $tag"
      if ! doctl registry repository delete-tag "$REPOSITORY" "$tag" --force; then
        echo "    ERROR: Failed to delete tag: $tag"
      fi
    done
    echo "Operation completed successfully"
  fi
fi
