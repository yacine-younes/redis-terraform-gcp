#!/bin/bash

## commons

apt-get -y update
apt-get -y install vim
apt-get -y install iotop
apt-get -y install iputils-ping
sudo apt install net-tools 

apt-get install -y netcat
apt-get install -y dnsutils

sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
apt-cache policy docker-ce
sudo apt-get install -y docker-ce



export DEBIAN_FRONTEND=noninteractive
export TZ="UTC"
apt-get install -y tzdata
ln -fs /usr/share/zoneinfo/Europe/Paris /etc/localtime
dpkg-reconfigure --frontend noninteractive tzdata

## memtier (this will install it for all users)
mkdir /home/ubuntu/install
cd /home/ubuntu/install
apt-get -y install build-essential autoconf automake libpcre3-dev libevent-dev pkg-config zlib1g-dev libssl-dev
wget -O memtier.tar.gz https://github.com/RedisLabs/memtier_benchmark/archive/refs/tags/1.4.0.tar.gz
tar xfz memtier.tar.gz
mv memtier_benchmark-* memtier
pushd memtier
 autoreconf -ivf
 ./configure
 make
 make install
popd

echo "${nodes}" >> install.log
echo "${cluster_dns_suffix}" >> install.log
#TODO /etc/hosts

## redis-benchmark and redis-cli
wget -O redis-stack.tar.gz https://redismodules.s3.amazonaws.com/redis-stack/redis-stack-server-6.2.0-v1.bionic.x86_64.tar.gz
tar xfz redis-stack.tar.gz
mv redis-stack-* redis-stack
mkdir -p /home/ubuntu/.local/bin
ln -s /home/ubuntu/install/redis-stack/bin/redis-benchmark /home/ubuntu/.local/bin/redis-benchmark
ln -s /home/ubuntu/install/redis-stack/bin/redis-cli /home/ubuntu/.local/bin/redis-cli

## utility scripts from the Git repo ./scripts folder
apt-get -y install unzip
wget https://github.com/alexvasseur/redis-terraform-gcp/archive/refs/heads/main.zip
unzip main.zip
mv redis-terraform-gcp-main/scripts/ .
chmod u+x scripts/*.sh

# for "sudo su - ubuntu"
chown -R ubuntu:ubuntu /home/ubuntu/install
chown -R ubuntu:ubuntu /home/ubuntu/.local

# install RDI
## RDI CLI
wget https://qa-onprem.s3.amazonaws.com/redis-di/latest/redis-di-ubuntu20.04-latest.tar.gz -O /tmp/redis-di.tar.gz
sudo tar xvf /tmp/redis-di.tar.gz -C /usr/local/bin/

# RDI
wget https://qa-onprem.s3.amazonaws.com/redis-di/latest/redis-di-offline-ubuntu20.04-latest.tar.gz -O /tmp/redis-di-offline.tar.gz
wget https://qa-onprem.s3.amazonaws.com/redis-di/debezium/debezium_server_2.3.0.Final_offline.tar.gz -O /tmp/debezium_server.Final_offline.tar.gz
wget https://redismodules.s3.amazonaws.com/redisgears/redisgears.Linux-ubuntu20.04-x86_64.1.2.6-withdeps.zip -O /tmp/redis-gears.zip
sleep 300

curl -k -u "admin@redis.io:demo" -X POST -F "module=@/tmp/redis-gears.zip" https://node1.yacine-default.demo.redislabs.com:9443/v2/modules
sleep 30

redis-di create --silent --cluster-host node1.yacine-default.demo.redislabs.com --cluster-user admin@redis.io --cluster-password demo
sudo docker load < /tmp/debezium_server.Final_offline.tar.gz
sudo docker tag debezium/server:2.3.0.Final_offline debezium/server:Final
sudo docker tag debezium/server:2.3.0.Final_offline debezium/server:latest
#sudo docker run --name some-mysql -d mysql
#sudo docker run --name some-mysql -e MYSQL_ROOT_PASSWORD=demo -d mysql -p 3306:11000

sleep 10
redis-di scaffold --db-type mysql --dir /home/ubuntu/debezium

sleep 10
sudo docker run --name mysql -d -p 11000:3306 -e MYSQL_ROOT_PASSWORD=demo -e MYSQL_ROOT_HOST="%" --restart unless-stopped mysql

sleep 10
sudo sed -i 's/debezium.sink.redis.address=<RDI_HOST>:<RDI_PORT>/debezium.sink.redis.address=redis-12001.cluster.yacine-default.demo.redislabs.com:12001/g' debezium/debezium/application.properties
sudo sed -i 's/debezium.sink.redis.password=<RDI_PASSWORD>/#debezium.sink.redis.password=<RDI_PASSWORD>/g' /home/ubuntu/debezium/debezium/application.properties

sudo sed -i 's/debezium.source.database.hostname=<SOURCE_DB_HOST>/debezium.source.database.hostname=172.17.0.1/g' /home/ubuntu/debezium/debezium/application.properties
sudo sed -i 's/debezium.source.database.port=<SOURCE_DB_PORT>/debezium.source.database.port=11000/g' /home/ubuntu/debezium/debezium/application.properties
sudo sed -i 's/debezium.source.database.user=<SOURCE_DB_USER>/debezium.source.database.user=root/g' /home/ubuntu/debezium/debezium/application.properties
sudo sed -i 's/debezium.source.database.password=<SOURCE_DB_PASSWORD>/debezium.source.database.password=demo/g' /home/ubuntu/debezium/debezium/application.properties
sudo sed -i 's/debezium.source.topic.prefix=<SOURCE_LOGICAL_SERVER_NAME>/debezium.source.topic.prefix=redis/g' /home/ubuntu/debezium/debezium/application.properties
sudo sed -i 's/debezium.sink.redis.address=<RDI_HOST>:<RDI_PORT>/debezium.sink.redis.address=redis-12001.cluster.yacine-default.demo.redislabs.com:12001/g' debezium/debezium/application.properties

sleep 10
sudo docker run -d --name debezium --restart always -v $PWD/debezium/debezium:/debezium/conf --log-driver local --log-opt max-size=100m --log-opt max-file=4 --log-opt mode=non-blocking debezium/server:2.1.1.Final

#### install gh cli
sudo mkdir -p -m 755 /etc/apt/keyrings && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
&& sudo apt update \
&& sudo apt install gh -y

sudo apt update
sudo apt install gh
#### end of install gh cli