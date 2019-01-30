# RabbitMQ Federation Test Script

We need to test federation between two RabbitMQ servers.  We'll create two RabbitMQ Docker containers which
we'll arbitrarily call **rabbit-left** and **rabbit-right**, create some exchanges and queues on each server, 
and then federate the two servers with upstream links and policies.  We've got one script that uses good old
**amqp** links and one that uses **ampqs** links (over TLS).

The non-TLS script, when run, will do the following:

   * Create a few directories and files
   * Build and start both server containers with Docker Compose
   * Use the *Management HTTP API* to create users, vhosts, exchanges, queues, upstream links and policies on each server.
   * Dump the configuration from each server to files in the ./definitions directory.

Ths TLS script, when run, will do the following:

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

## Result
Once the servers are running, configured and federated, the logs fill up with messages that look like the following.
Everything appears to work; messages seem to flow properly between servers.  These log messages popping up every
thirty seconds, however, are a bit concerning.  What's up with these?

```bash
rabbit-right    | 2019-01-25 20:09:28.010 [info] <0.962.0> accepting AMQP connection <0.962.0> (192.168.160.2:51781 -> 192.168.160.3:5671)
rabbit-left     | 2019-01-25 20:09:28.042 [info] <0.972.0> accepting AMQP connection <0.972.0> (192.168.160.3:57199 -> 192.168.160.2:5671)
rabbit-right    | 2019-01-25 20:09:28.043 [info] <0.962.0> connection <0.962.0> (192.168.160.2:51781 -> 192.168.160.3:5671): user 'admin' authenticated and granted access to vhost 'rabbit.federation.test.vhost'
rabbit-left     | 2019-01-25 20:09:28.048 [info] <0.972.0> connection <0.972.0> (192.168.160.3:57199 -> 192.168.160.2:5671): user 'admin' authenticated and granted access to vhost 'rabbit.federation.test.vhost'
rabbit-right    | 2019-01-25 20:09:28.053 [info] <0.962.0> closing AMQP connection <0.962.0> (192.168.160.2:51781 -> 192.168.160.3:5671, vhost: 'rabbit.federation.test.vhost', user: 'admin')
rabbit-left     | 2019-01-25 20:09:28.055 [info] <0.972.0> closing AMQP connection <0.972.0> (192.168.160.3:57199 -> 192.168.160.2:5671, vhost: 'rabbit.federation.test.vhost', user: 'admin')

rabbit-right    | 2019-01-25 20:09:58.068 [info] <0.1007.0> accepting AMQP connection <0.1007.0> (192.168.160.2:57417 -> 192.168.160.3:5671)
rabbit-left     | 2019-01-25 20:09:58.068 [info] <0.1006.0> accepting AMQP connection <0.1006.0> (192.168.160.3:37273 -> 192.168.160.2:5671)
rabbit-right    | 2019-01-25 20:09:58.074 [info] <0.1007.0> connection <0.1007.0> (192.168.160.2:57417 -> 192.168.160.3:5671): user 'admin' authenticated and granted access to vhost 'rabbit.federation.test.vhost'
rabbit-left     | 2019-01-25 20:09:58.075 [info] <0.1006.0> connection <0.1006.0> (192.168.160.3:37273 -> 192.168.160.2:5671): user 'admin' authenticated and granted access to vhost 'rabbit.federation.test.vhost'
rabbit-right    | 2019-01-25 20:09:58.080 [info] <0.1007.0> closing AMQP connection <0.1007.0> (192.168.160.2:57417 -> 192.168.160.3:5671, vhost: 'rabbit.federation.test.vhost', user: 'admin')
rabbit-left     | 2019-01-25 20:09:58.080 [info] <0.1006.0> closing AMQP connection <0.1006.0> (192.168.160.3:37273 -> 192.168.160.2:5671, vhost: 'rabbit.federation.test.vhost', user: 'admin')

rabbit-right    | 2019-01-25 20:10:28.113 [info] <0.1048.0> accepting AMQP connection <0.1048.0> (192.168.160.2:57897 -> 192.168.160.3:5671)
rabbit-right    | 2019-01-25 20:10:28.118 [info] <0.1048.0> connection <0.1048.0> (192.168.160.2:57897 -> 192.168.160.3:5671): user 'admin' authenticated and granted access to vhost 'rabbit.federation.test.vhost'
rabbit-left     | 2019-01-25 20:10:28.120 [info] <0.1049.0> accepting AMQP connection <0.1049.0> (192.168.160.3:58987 -> 192.168.160.2:5671)
rabbit-left     | 2019-01-25 20:10:28.124 [info] <0.1049.0> connection <0.1049.0> (192.168.160.3:58987 -> 192.168.160.2:5671): user 'admin' authenticated and granted access to vhost 'rabbit.federation.test.vhost'
rabbit-right    | 2019-01-25 20:10:28.126 [info] <0.1048.0> closing AMQP connection <0.1048.0> (192.168.160.2:57897 -> 192.168.160.3:5671, vhost: 'rabbit.federation.test.vhost', user: 'admin')
rabbit-left     | 2019-01-25 20:10:28.140 [info] <0.1049.0> closing AMQP connection <0.1049.0> (192.168.160.3:58987 -> 192.168.160.2:5671, vhost: 'rabbit.federation.test.vhost', user: 'admin')
```

# Response

Aaaaaand here's the response that I received via the [RabbitMQ Mailing List](https://groups.google.com/forum/#!forum/rabbitmq-users):

https://groups.google.com/forum/#!topic/rabbitmq-users/Zu-1bQ79Z6Y
