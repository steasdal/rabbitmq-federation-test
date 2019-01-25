# RabbitMQ Federation Test Script

We need to test federation over TLS between two RabbitMQ servers.  We'll create two RabbitMQ Docker containers which
we'll arbitrarily call *rabbit-left* and *rabbit-right*, create some exchanges and queues on each server, and then
federate the two servers with upstream links and policies.  This script, when run, will do the following:

   * Create a few directories and files
   * Create a Certificate Authority
   * Create server and client certificates for each server.
   * Build and start both server containers with Docker Compose
   * Use the *Management HTTP API* to create users, vhosts, exchanges, queues, upstream links and policies on each server.
   * Dump the configuration from each server to files in the ./definitions directory.
   
## Requirements
You'll need to following tools to run this script:

   * bash
   * curl
   * docker
