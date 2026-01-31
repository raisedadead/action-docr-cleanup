# Contributing

Thank you for your interest in contributing to this project!

## Development

1. Fork the repository
2. Create a feature branch: `git checkout -b my-feature`
3. Make your changes
4. Test your changes locally
5. Commit with a descriptive message
6. Push to your fork and open a Pull Request

## Testing Locally

You can test the action locally using the entrypoint script:

```bash
# Dry run (no actual deletions)
./entrypoint.sh -d -n 7 your-repository-name

# With keep-last option
./entrypoint.sh -d -n 7 --keep-last 5 your-repository-name
```

Requirements:
- `doctl` CLI installed and authenticated
- `jq` installed

## Releasing

This project uses semantic versioning and automated releases.

### Creating a Release

1. Ensure all changes are merged to the main branch
2. Create and push a semantic version tag:

```bash
git checkout main
git pull origin main
git tag v1.0.0
git push origin v1.0.0
```

3. The release workflow will automatically:
   - Create a GitHub Release with auto-generated notes
   - Update major version tag (`v1` → points to `v1.0.0`)
   - Update minor version tag (`v1.0` → points to `v1.0.0`)

### Version Guidelines

- **Patch** (`v1.0.1`): Bug fixes, documentation updates
- **Minor** (`v1.1.0`): New features, backward-compatible changes
- **Major** (`v2.0.0`): Breaking changes

### Users Reference Tags

Users can reference this action at different stability levels:

```yaml
# Always get latest v1.x.x (recommended)
- uses: raisedadead/action-docr-cleanup@v1

# Pin to minor version
- uses: raisedadead/action-docr-cleanup@v1.0

# Pin to exact version
- uses: raisedadead/action-docr-cleanup@v1.0.0
```
