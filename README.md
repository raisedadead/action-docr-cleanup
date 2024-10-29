# DigitalOcean Registry Cleanup Action

This action helps manage tags in a DigitalOcean container registry by providing flexible cleanup options. It can delete tags based on age and/or keep a specific number of recent tags. The action always preserves the "latest" tag.

## Features

- Delete tags older than a specified number of days
- Keep a specified number of most recent tags
- Safety check to prevent accidental deletion of all images
- Dry run mode to preview changes
- Preserves the "latest" tag

## Inputs

### `repository_name`
**Required**. Name of the DigitalOcean container registry repository.

### `days`
Number of days. Tags older than these many days will be deleted.
- Default: "2"
- Optional

### `keep_last`
Number of most recent tags to keep, regardless of age.
- Optional
- Example: "3" will keep the three most recent tags

### `dry_run`
If set to true, shows what would be deleted without making any changes.
- Default: "false"
- Optional

### `bypass_safety`
Bypass the safety check that prevents deletion when no recent images exist.
- Default: "false"
- Optional

## Usage Examples

### Basic Usage
```yaml
- name: Install doctl
  uses: digitalocean/action-doctl@v2
  with:
    token: ${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }}

- name: Log in to DigitalOcean Container Registry
  run: doctl registry login --expiry-seconds 1200

- name: Cleanup Registry
  uses: raisedadead/action-docr-cleanup@v1
  with:
    repository_name: 'your-repository-name'
    days: '7'
```

### Keep Recent Tags
```yaml
- uses: raisedadead/action-docr-cleanup@v1
  with:
    repository_name: 'your-repository-name'
    days: '7'
    keep_last: '3'  # Keep 3 most recent tags
```

### Dry Run Mode
```yaml
- uses: raisedadead/action-docr-cleanup@v1
  with:
    repository_name: 'your-repository-name'
    days: '7'
    dry_run: 'true'  # Preview changes without deleting
```

### Bypass Safety Check
```yaml
- uses: raisedadead/action-docr-cleanup@v1
  with:
    repository_name: 'your-repository-name'
    days: '7'
    bypass_safety: 'true'  # Disable safety checks
```

## Manual Usage

You can also run the script directly after installing [doctl](https://docs.digitalocean.com/reference/doctl/) and authenticating:

```bash
# Login to registry
doctl registry login --expiry-seconds 1200

# View help
./entrypoint.sh -h

# Dry run with 7-day threshold
./entrypoint.sh -d -n 7 your-repository-name

# Keep 3 most recent tags, delete others older than 7 days
./entrypoint.sh -n 7 --keep-last 3 your-repository-name

# Bypass safety check
./entrypoint.sh -n 7 -b your-repository-name
```

## Safety Features

1. The "latest" tag is always preserved
2. By default, the action won't delete tags if no images newer than the threshold exist
3. Dry run mode allows previewing changes before actual deletion

## License

Licensed under the [MIT](LICENSE) License. Feel free to extend, reuse, and share.
