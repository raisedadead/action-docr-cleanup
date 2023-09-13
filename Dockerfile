# Use a base image with bash support
FROM debian:bullseye-slim

# Install jq
RUN apt-get update && apt-get install -y jq

# Copy the script to the docker image
COPY entrypoint.sh /entrypoint.sh

# Make the script executable
RUN chmod +x /entrypoint.sh

# Set the entrypoint for the Docker container
ENTRYPOINT ["/entrypoint.sh"]
