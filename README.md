# DigitalOcean Registry Cleanup Action

This action deletes tags older than a specified number of days from a
DigitalOcean container registry, excluding the "latest" tag. Before using this
action, ensure you've set up `doctl` and authenticated with DigitalOcean.

## Inputs

### `repository_name`

Name of the DigitalOcean container registry repository. Required.

### `dry_run`

If set to true, it will display tags to be deleted without actually deleting
them. Default is "false".

### `days`

Number of days. Tags older than these many days will be deleted. Default is "2".

## Example usage

```yml
- name: Install doctl
  uses: digitalocean/action-doctl@v2
  with:
    token: ${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }}

- name: Log in to DigitalOcean Container Registry with short-lived credentials
  run: doctl registry login --expiry-seconds 1200

- uses: raisedadead/action-docr-cleanup@v1
  with:
  repository_name: 'your-repository-name'
  dry_run: 'true'
  days: '7'
```
