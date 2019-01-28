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
rm -rf definitions

mkdir -p definitions

########################################################################################################################

echo "Creating the ./rabbitmq.conf file that we'll use to configure both the left and right servers..."

cat << EOT >> rabbitmq.conf
loopback_users.guest             = false
EOT

########################################################################################################################

echo "Creating the ./Dockerfile-Left file that Docker Compose will use to build the rabbit-left image..."

cat << EOT >> Dockerfile-Left
FROM rabbitmq:3.7.8

RUN rabbitmq-plugins enable --offline rabbitmq_management && \
    rabbitmq-plugins enable rabbitmq_federation --offline && \
    rabbitmq-plugins enable rabbitmq_federation_management --offline && \
    apt-get update && apt-get -y install python nano curl jq less

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

curl -u ${admin_name}:${admin_pass} -X PUT http://localhost:${left_server_port}/api/parameters/federation-upstream/${vhost_name}/left.upstream \
-H "Content-Type: application/json" \
-d @- << EOF
{
    "value": {
        "trust-user-id": false,
        "uri": "amqp://${admin_name}:${admin_pass}@${right_server_hostname}"
    }
}
EOF

curl -u ${admin_name}:${admin_pass} -X PUT http://localhost:${right_server_port}/api/parameters/federation-upstream/${vhost_name}/right.upstream \
-H "Content-Type: application/json" \
-d @- << EOF
{
    "value": {
        "trust-user-id": false,
        "uri": "amqp://${admin_name}:${admin_pass}@${left_server_hostname}"
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

curl -s -u ${admin_name}:${admin_pass} http://localhost:${left_server_port}/api/definitions  > ./definitions/rabbit.left.json
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
echo "#   and can be accessed at the following URLs using admin/admin:         #"
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

echo

read -p "Press ENTER to delete the files created by this script or ctrl+c to exit..."

echo

echo "deleting the files and directories created by this script..."

rm -f rabbitmq.conf
rm -f Dockerfile-Left
rm -f Dockerfile-Right
rm -f docker-compose.yml
rm -rf testca
rm -rf definitions

echo

echo "*** DONE ***"

echo
