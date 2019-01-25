#!/usr/bin/env bash

##############################
#           _                #
#  ___  ___| |_ _   _ _ __   #
# / __|/ _ \ __| | | | '_ \  #
# \__ \  __/ |_| |_| | |_) | #
# |___/\___|\__|\__,_| .__/  #
#                    |_|     #
##############################

echo "Preparing all the things..."

left_server_hostname=rabbit.left
left_server_port=8081

right_server_hostname=rabbit.right
right_server_port=8082

# admin username and password for both left and right servers
admin_name=admin
admin_pass=admin

# name of the virtual host (vhost) that we'll use for everything.
vhost_name=rabbit.federation.test.vhost

########################################################################################################################

rm -f rabbitmq.conf
rm -f Dockerfile-Left
rm -f Dockerfile-Right
rm -f docker-compose.yml
rm -rf testca
rm -rf definitions

mkdir -p testca/certs \
         testca/private \
         testca/left-server \
         testca/left-client \
         testca/right-server \
         testca/right-client \
         definitions

chmod 700 testca/private
echo 01 > testca/serial
touch testca/index.txt

########################################################################################################################

echo "Creating the ./testca/openssl.cnf file that'll be used in several steps of the CA/Certificate creation/signing process..."

cat << EOT >> testca/openssl.cnf
[ ca ]
default_ca = testca

[ testca ]
dir = .
certificate = \$dir/ca_certificate_bundle.pem
database = \$dir/index.txt
new_certs_dir = \$dir/certs
private_key = \$dir/private/ca_private_key.pem
serial = \$dir/serial

default_crl_days = 7
default_days = 365
default_md = sha256

policy = testca_policy
x509_extensions = certificate_extensions

[ testca_policy ]
commonName = supplied
stateOrProvinceName = optional
countryName = optional
emailAddress = optional
organizationName = optional
organizationalUnitName = optional
domainComponent = optional

[ certificate_extensions ]
basicConstraints = CA:false

[ req ]
default_bits = 2048
default_keyfile = ./private/ca_private_key.pem
default_md = sha256
prompt = yes
distinguished_name = root_ca_distinguished_name
x509_extensions = root_ca_extensions

[ root_ca_distinguished_name ]
commonName = hostname

[ root_ca_extensions ]
basicConstraints = CA:true
keyUsage = keyCertSign, cRLSign

[ client_ca_extensions ]
basicConstraints = CA:false
keyUsage = digitalSignature,keyEncipherment
extendedKeyUsage = 1.3.6.1.5.5.7.3.2

[ server_ca_extensions ]
basicConstraints = CA:false
keyUsage = digitalSignature,keyEncipherment
extendedKeyUsage = 1.3.6.1.5.5.7.3.1
EOT

########################################################################################################################

echo "Creating the ./rabbitmq.conf file that we'll use to configure both the left and right servers..."

cat << EOT >> rabbitmq.conf
listeners.ssl.default            = 5671
loopback_users.guest             = false
ssl_options.verify               = verify_peer
ssl_options.fail_if_no_peer_cert = false
ssl_options.cacertfile           = /etc/ssl/certs/server/ca_certificate_bundle.pem
ssl_options.certfile             = /etc/ssl/certs/server/server_certificate.pem
ssl_options.keyfile              = /etc/ssl/certs/server/server_key.pem
EOT

########################################################################################################################

echo "Creating the ./Dockerfile-Left file that Docker Compose will use to build the rabbit-left image..."

cat << EOT >> Dockerfile-Left
FROM rabbitmq:3.7.8

RUN rabbitmq-plugins enable --offline rabbitmq_management && \
    rabbitmq-plugins enable rabbitmq_federation --offline && \
    rabbitmq-plugins enable rabbitmq_federation_management --offline && \
    apt-get update && apt-get -y install python nano curl jq less

COPY testca/ca_certificate_bundle.pem /etc/ssl/certs/server/
COPY testca/left-server/server_certificate.pem /etc/ssl/certs/server/
COPY testca/left-server/server_key.pem /etc/ssl/certs/server/

COPY testca/ca_certificate_bundle.pem /etc/ssl/certs/client/
COPY testca/left-client/client_certificate.pem /etc/ssl/certs/client/
COPY testca/left-client/client_key.pem /etc/ssl/certs/client/

COPY rabbitmq.conf /etc/rabbitmq/
EOT

########################################################################################################################

echo "Creating the ./Dockerfile-Right file that Docker Compose will use to build the rabbit-right image..."

cat << EOT >> Dockerfile-Right
FROM rabbitmq:3.7.8

RUN rabbitmq-plugins enable --offline rabbitmq_management && \
    rabbitmq-plugins enable rabbitmq_federation --offline && \
    rabbitmq-plugins enable rabbitmq_federation_management --offline && \
    apt-get update && apt-get -y install python nano curl jq less

COPY testca/ca_certificate_bundle.pem /etc/ssl/certs/server/
COPY testca/right-server/server_certificate.pem /etc/ssl/certs/server/
COPY testca/right-server/server_key.pem /etc/ssl/certs/server/

COPY testca/ca_certificate_bundle.pem /etc/ssl/certs/client/
COPY testca/right-client/client_certificate.pem /etc/ssl/certs/client/
COPY testca/right-client/client_key.pem /etc/ssl/certs/client/

COPY rabbitmq.conf /etc/rabbitmq/

EOT

########################################################################################################################

echo "Creating the ./docker-compose.yml file..."

cat << EOT >> docker-compose.yml
version: '2.2'
services:

  rabbit.left:
    image: rabbit-left
    container_name: rabbit-left
    hostname: rabbit.left
    build:
      context: .
      dockerfile: Dockerfile-Left
    networks:
      - rabbit
    ports:
      - ${left_server_port}:15672

  rabbit.right:
    image: rabbit-right
    container_name: rabbit-right
    hostname: rabbit.right
    build:
      context: .
      dockerfile: Dockerfile-Right
    networks:
      - rabbit
    ports:
      - ${right_server_port}:15672

networks:
  rabbit:
    driver: bridge
EOT

######################################################
#                _   _  __ _           _             #
#   ___ ___ _ __| |_(_)/ _(_) ___ __ _| |_ ___  ___  #
#  / __/ _ \ '__| __| | |_| |/ __/ _` | __/ _ \/ __| #
# | (_|  __/ |  | |_| |  _| | (_| (_| | ||  __/\__ \ #
#  \___\___|_|   \__|_|_| |_|\___\__,_|\__\___||___/ #
#                                                    #
######################################################

echo "Creating a Certificate Authority and using it to generate self-signed server and client certs for both servers..."

# Create Certificate Authority
docker run --rm -v $(pwd)/testca:/testca -w /testca -it frapsoft/openssl req -x509 -config openssl.cnf -newkey rsa:2048 -days 365 -out ca_certificate_bundle.pem -outform PEM -subj /CN=MYTESTCA/ -nodes
docker run --rm -v $(pwd)/testca:/testca -w /testca -it frapsoft/openssl x509 -in ca_certificate_bundle.pem -out ca_certificate_bundle.cer -outform DER

# Left Server
docker run --rm -v $(pwd)/testca:/testca -w /testca -it frapsoft/openssl genrsa -out left-server/server_key.pem 2048
docker run --rm -v $(pwd)/testca:/testca -w /testca -it frapsoft/openssl req -new -key left-server/server_key.pem -out left-server/req.pem -outform PEM -subj /CN=${left_server_hostname}/O=server/ -nodes
docker run --rm -v $(pwd)/testca:/testca -w /testca -it frapsoft/openssl ca -config openssl.cnf -in left-server/req.pem -out left-server/server_certificate.pem -notext -batch -extensions server_ca_extensions

# Left Client
docker run --rm -v $(pwd)/testca:/testca -w /testca -it frapsoft/openssl genrsa -out left-client/client_key.pem 2048
docker run --rm -v $(pwd)/testca:/testca -w /testca -it frapsoft/openssl req -new -key left-client/client_key.pem -out left-client/req.pem -outform PEM -subj /CN=${right_server_hostname}/O=client/ -nodes
docker run --rm -v $(pwd)/testca:/testca -w /testca -it frapsoft/openssl ca -config openssl.cnf -in left-client/req.pem -out left-client/client_certificate.pem -notext -batch -extensions client_ca_extensions

# Right Server
docker run --rm -v $(pwd)/testca:/testca -w /testca -it frapsoft/openssl genrsa -out right-server/server_key.pem 2048
docker run --rm -v $(pwd)/testca:/testca -w /testca -it frapsoft/openssl req -new -key right-server/server_key.pem -out right-server/req.pem -outform PEM -subj /CN=${right_server_hostname}/O=server/ -nodes
docker run --rm -v $(pwd)/testca:/testca -w /testca -it frapsoft/openssl ca -config openssl.cnf -in right-server/req.pem -out right-server/server_certificate.pem -notext -batch -extensions server_ca_extensions

# Right Client
docker run --rm -v $(pwd)/testca:/testca -w /testca -it frapsoft/openssl genrsa -out right-client/client_key.pem 2048
docker run --rm -v $(pwd)/testca:/testca -w /testca -it frapsoft/openssl req -new -key right-client/client_key.pem -out right-client/req.pem -outform PEM -subj /CN=${left_server_hostname}/O=client/ -nodes
docker run --rm -v $(pwd)/testca:/testca -w /testca -it frapsoft/openssl ca -config openssl.cnf -in right-client/req.pem -out right-client/client_certificate.pem -notext -batch -extensions client_ca_extensions

#######################################
#      _             _                #
#  ___| |_ __ _ _ __| |_ _   _ _ __   #
# / __| __/ _` | '__| __| | | | '_ \  #
# \__ \ || (_| | |  | |_| |_| | |_) | #
# |___/\__\__,_|_|   \__|\__,_| .__/  #
#                             |_|     #
#######################################

echo "Building and starting the temporary RabbitMQ containers..."

docker-compose up -d

echo
echo "Sleeping for 30 seconds to let the two rabbit containers finish starting up..."
echo
echo "This would be a good time to open another terminal and run \"docker-compose logs -f\""
echo "so that you could follow along with all of the action as it's goin' down."
echo
sleep 30s

###############################
#        _               _    #
# __   _| |__   ___  ___| |_  #
# \ \ / / '_ \ / _ \/ __| __| #
#  \ V /| | | | (_) \__ \ |_  #
#   \_/ |_| |_|\___/|___/\__| #
#                             #
###############################

echo "creating the \"${vhost_name}\" vhost in each server..."

curl -u guest:guest -XPUT -H "content-type:application/json" http://localhost:${left_server_port}/api/vhosts/${vhost_name}
curl -u guest:guest -XPUT -H "content-type:application/json" http://localhost:${right_server_port}/api/vhosts/${vhost_name}

#############################
#  _   _ ___  ___ _ __ ___  #
# | | | / __|/ _ \ '__/ __| #
# | |_| \__ \  __/ |  \__ \ #
#  \__,_|___/\___|_|  |___/ #
#                           #
#############################

echo "creating and setting permissions for the \"admin\" user on both servers..."

################################################################
# Add an 'admin' user to each broker and grant full permissions.
################################################################

curl -u guest:guest -XPUT http://localhost:${left_server_port}/api/users/${admin_name} \
-H "Content-Type: application/json" \
-d @- << EOF
{
	"password":"${admin_pass}","tags":"administrator"
}
EOF

curl -u guest:guest -XPUT http://localhost:${right_server_port}/api/users/${admin_name} \
-H "Content-Type: application/json" \
-d @- << EOF
{
	"password":"${admin_pass}","tags":"administrator"
}
EOF

curl -u guest:guest -XPUT http://localhost:${left_server_port}/api/permissions/${vhost_name}/${admin_name} \
-H "Content-Type: application/json" \
-d @- << EOF
{
	"configure":".*", "write":".*", "read":".*"
}
EOF

curl -u guest:guest -XPUT http://localhost:${right_server_port}/api/permissions/${vhost_name}/${admin_name} \
-H "Content-Type: application/json" \
-d @- << EOF
{
	"configure":".*", "write":".*", "read":".*"
}
EOF

################################################################
#       _           _                                          #
#   ___| |_   _ ___| |_ ___ _ __   _ __   __ _ _ __ ___   ___  #
#  / __| | | | / __| __/ _ \ '__| | '_ \ / _` | '_ ` _ \ / _ \ #
# | (__| | |_| \__ \ ||  __/ |    | | | | (_| | | | | | |  __/ #
#  \___|_|\__,_|___/\__\___|_|    |_| |_|\__,_|_| |_| |_|\___| #
#                                                              #
################################################################

echo "setting the cluster name to \"rabbit-cluster\" on both brokers..."

curl -u ${admin_name}:${admin_pass} -H "Content-Type: application/json" -X PUT http://localhost:${left_server_port}/api/cluster-name -d "{\"name\":\"rabbit-cluster\"}"
curl -u ${admin_name}:${admin_pass} -H "Content-Type: application/json" -X PUT http://localhost:${right_server_port}/api/cluster-name -d "{\"name\":\"rabbit-cluster\"}"


############################################################################################################
#                _                                                   _                                     #
#   _____  _____| |__   __ _ _ __   __ _  ___  ___    __ _ _ __   __| |   __ _ _   _  ___ _   _  ___  ___  #
#  / _ \ \/ / __| '_ \ / _` | '_ \ / _` |/ _ \/ __|  / _` | '_ \ / _` |  / _` | | | |/ _ \ | | |/ _ \/ __| #
# |  __/>  < (__| | | | (_| | | | | (_| |  __/\__ \ | (_| | | | | (_| | | (_| | |_| |  __/ |_| |  __/\__ \ #
#  \___/_/\_\___|_| |_|\__,_|_| |_|\__, |\___||___/  \__,_|_| |_|\__,_|  \__, |\__,_|\___|\__,_|\___||___/ #
#                                  |___/                                    |_|                            #
############################################################################################################

echo "creating left server exchange..."

# create a direct exchange: 'left.exchange'
curl -u ${admin_name}:${admin_pass} -XPUT http://localhost:${left_server_port}/api/exchanges/${vhost_name}/left.exchange \
-H "Content-Type: application/json" \
-d @- << EOF
{
	"type":"direct", "durable":true
}
EOF

echo "creating right server exchange..."

# create a direct exchange 'right.exchange'
curl -u ${admin_name}:${admin_pass} -XPUT http://localhost:${right_server_port}/api/exchanges/${vhost_name}/right.exchange \
-H "Content-Type: application/json" \
-d @- << EOF
{
	"type":"direct", "durable":true
}
EOF

echo "creating left server queues and bindings..."

curl -u ${admin_name}:${admin_pass} -H "Content-Type: application/json" -X PUT http://localhost:${left_server_port}/api/queues/${vhost_name}/left.queue.one -d "{\"durable\":true}"
curl -u ${admin_name}:${admin_pass} -H "Content-Type: application/json" -X PUT http://localhost:${left_server_port}/api/queues/${vhost_name}/left.queue.two -d "{\"durable\":true}"
curl -u ${admin_name}:${admin_pass} -H "Content-Type: application/json" -X PUT http://localhost:${left_server_port}/api/queues/${vhost_name}/left.queue.three -d "{\"durable\":true}"

curl -u ${admin_name}:${admin_pass} -H "Content-Type: application/json" -X POST http://localhost:${left_server_port}/api/bindings/${vhost_name}/e/left.exchange/q/left.queue.one -d "{\"routing_key\":\"left-queue-one\"}"
curl -u ${admin_name}:${admin_pass} -H "Content-Type: application/json" -X POST http://localhost:${left_server_port}/api/bindings/${vhost_name}/e/left.exchange/q/left.queue.two -d "{\"routing_key\":\"left-queue-two\"}"
curl -u ${admin_name}:${admin_pass} -H "Content-Type: application/json" -X POST http://localhost:${left_server_port}/api/bindings/${vhost_name}/e/left.exchange/q/left.queue.three -d "{\"routing_key\":\"left-queue-three\"}"

echo "creating right server queues and bindings..."

curl -u ${admin_name}:${admin_pass} -H "Content-Type: application/json" -X PUT http://localhost:${right_server_port}/api/queues/${vhost_name}/right.queue.one -d "{\"durable\":true}"
curl -u ${admin_name}:${admin_pass} -H "Content-Type: application/json" -X PUT http://localhost:${right_server_port}/api/queues/${vhost_name}/right.queue.two -d "{\"durable\":true}"
curl -u ${admin_name}:${admin_pass} -H "Content-Type: application/json" -X PUT http://localhost:${right_server_port}/api/queues/${vhost_name}/right.queue.three -d "{\"durable\":true}"

curl -u ${admin_name}:${admin_pass} -H "Content-Type: application/json" -X POST http://localhost:${right_server_port}/api/bindings/${vhost_name}/e/right.exchange/q/right.queue.one -d "{\"routing_key\":\"right-queue-one\"}"
curl -u ${admin_name}:${admin_pass} -H "Content-Type: application/json" -X POST http://localhost:${right_server_port}/api/bindings/${vhost_name}/e/right.exchange/q/right.queue.two -d "{\"routing_key\":\"right-queue-two\"}"
curl -u ${admin_name}:${admin_pass} -H "Content-Type: application/json" -X POST http://localhost:${right_server_port}/api/bindings/${vhost_name}/e/right.exchange/q/right.queue.three -d "{\"routing_key\":\"right-queue-three\"}"

###################################################################################################################################
#                  _                              _               _                               _               _ _             #
#  _   _ _ __  ___| |_ _ __ ___  __ _ _ __ ___   | |__  _ __ ___ | | _____ _ __    __ _ _ __   __| |  _ __   ___ | (_) ___ _   _  #
# | | | | '_ \/ __| __| '__/ _ \/ _` | '_ ` _ \  | '_ \| '__/ _ \| |/ / _ \ '__|  / _` | '_ \ / _` | | '_ \ / _ \| | |/ __| | | | #
# | |_| | |_) \__ \ |_| | |  __/ (_| | | | | | | | |_) | | | (_) |   <  __/ |    | (_| | | | | (_| | | |_) | (_) | | | (__| |_| | #
#  \__,_| .__/|___/\__|_|  \___|\__,_|_| |_| |_| |_.__/|_|  \___/|_|\_\___|_|     \__,_|_| |_|\__,_| | .__/ \___/|_|_|\___|\__, | #
#       |_|                                                                                          |_|                   |___/  #
###################################################################################################################################

echo "setting the upstream broker and creating the federation policy on each broker..."

cacertfile="/etc/ssl/certs/client/ca_certificate_bundle.pem"
certfile="/etc/ssl/certs/client/client_certificate.pem"
keyfile="/etc/ssl/certs/client/client_key.pem"
verify="verify_peer"
fail_if_no_peer_cert="true"
auth_mechanism="plain"

curl -u ${admin_name}:${admin_pass} -X PUT http://localhost:${left_server_port}/api/parameters/federation-upstream/${vhost_name}/left.upstream \
-H "Content-Type: application/json" \
-d @- << EOF
{
    "value": {
        "trust-user-id": false,
        "uri": "amqps://${admin_name}:${admin_pass}@${right_server_hostname}?cacertfile=${cacertfile}&certfile=${certfile}&keyfile=${keyfile}&verify=${verify}&server_name_indication=${right_server_hostname}&fail_if_no_peer_cert=${fail_if_no_peer_cert}&auth_mechanism=${auth_mechanism}"
    }
}
EOF

curl -u ${admin_name}:${admin_pass} -X PUT http://localhost:${right_server_port}/api/parameters/federation-upstream/${vhost_name}/right.upstream \
-H "Content-Type: application/json" \
-d @- << EOF
{
    "value": {
        "trust-user-id": false,
        "uri": "amqps://${admin_name}:${admin_pass}@${left_server_hostname}?cacertfile=${cacertfile}&certfile=${certfile}&keyfile=${keyfile}&verify=${verify}&server_name_indication=${left_server_hostname}&fail_if_no_peer_cert=${fail_if_no_peer_cert}&auth_mechanism=${auth_mechanism}"
    }
}
EOF

curl -u ${admin_name}:${admin_pass} -X PUT http://localhost:${left_server_port}/api/policies/${vhost_name}/left.policy \
-H "Content-Type: application/json" \
-d @- << EOF
{
    "pattern": "left.exchange",
    "definition": {
        "federation-upstream":"left.upstream"
    },
    "priority": 1,
    "apply-to": "exchanges"
}
EOF

curl -u ${admin_name}:${admin_pass} -X PUT http://localhost:${right_server_port}/api/policies/${vhost_name}/right.policy \
-H "Content-Type: application/json" \
-d @- << EOF
{
    "pattern": "right.exchange",
    "definition": {
        "federation-upstream":"right.upstream"
    },
    "priority": 1,
    "apply-to": "exchanges"
}
EOF

##################################################################################
#      _                             _       __ _       _ _   _                  #
#   __| |_   _ _ __ ___  _ __     __| | ___ / _(_)_ __ (_) |_(_) ___  _ __  ___  #
#  / _` | | | | '_ ` _ \| '_ \   / _` |/ _ \ |_| | '_ \| | __| |/ _ \| '_ \/ __| #
# | (_| | |_| | | | | | | |_) | | (_| |  __/  _| | | | | | |_| | (_) | | | \__ \ #
#  \__,_|\__,_|_| |_| |_| .__/   \__,_|\___|_| |_|_| |_|_|\__|_|\___/|_| |_|___/ #
#                       |_|                                                      #
##################################################################################

echo "dumping definitions to the ./definitions drectory..."

curl -s -u ${admin_name}:${admin_pass} http://localhost:${left_server_port}/api/definitions > ./definitions/rabbit.left.json
curl -s -u ${admin_name}:${admin_pass} http://localhost:${right_server_port}/api/definitions > ./definitions/rabbit.right.json

####################################################
#                             _ _                  #
# __      ___ __ __ _ _ __   (_) |_   _   _ _ __   #
# \ \ /\ / / '__/ _` | '_ \  | | __| | | | | '_ \  #
#  \ V  V /| | | (_| | |_) | | | |_  | |_| | |_) | #
#   \_/\_/ |_|  \__,_| .__/  |_|\__|  \__,_| .__/  #
#                    |_|                   |_|     #
#                                                  #
####################################################

echo
echo "##########################################################################"
echo "#                                                                        #"
echo "#   Configuration Complete!  The RabbitMQ containers are still running   #"
echo "#   and can be accessed at the following URLs:                           #"
echo "#                                                                        #"
echo "#       http://localhost:${left_server_port}   (the left broker)                        #"
echo "#       http://localhost:${right_server_port}   (the right broker)                       #"
echo "#                                                                        #"
echo "#   The RabbitMQ Management HTTP API (which is what all of the curl      #"
echo "#   statements in this script are using) can be accessed at either of    #"
echo "#   the following two URLs:                                              #"
echo "#                                                                        #"
echo "#       http://localhost:${left_server_port}/api                                        #"
echo "#       http://localhost:${right_server_port}/api                                        #"
echo "#                                                                        #"
echo "##########################################################################"
echo
read -p "Press ENTER to shutdown and remove the RabbitMQ containers..."

echo

echo "shutting down and removing the temporary RabbitMQ containers..."

docker-compose down --rmi all

echo "*** DONE ***"