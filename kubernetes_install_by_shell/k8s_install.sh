#!/bin/bash
#2018/02/24 by kevinkai
#Create for simple to deploy k8s Cluster
#Version V1.1

#环境变量
PWD=$(cd `dirname $0`; pwd)
# 集群 ip 多个 ip 以逗号分隔（根据实际情况修改）
# master的ip
MASTER_IPS=172.16.96.121,172.16.96.122
# node 的 ip
NODE_IPS=172.16.96.122,172.16.96.123
# etcd 集群的 ip
ETCD_IPS=172.16.96.121,172.16.96.122,172.16.96.123
# k8s master vip（根据实际情况修改）
CLUSTER_VIP=172.16.96.121
# haproxy 里配置的apiserver http frontend端口（根据实际情况修改）
HTTP_HAPROXY_PORT=8080

# haproxy 里配置的 apiserver https frontend 端口（根据实际情况修改）
HTTPS_HAPROXY_PORT=6443

###########################################################################################
###############################可根据实际需求修改#############################################
###########################################################################################

# kubernetes 服务 IP (预分配，一般是 SERVICE_CIDR 中第一个IP)（根据实际情况修改）
CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"

# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)（根据实际情况修改）
CLUSTER_DNS_SVC_IP="10.254.0.2"

# POD 网段 (Cluster CIDR），部署前路由不可达，部署后路由可达 (flanneld 保证)（根据实际情况修改）
CLUSTER_CIDR="172.30.0.0/16"

# 服务网段 (Service CIDR），部署前路由不可达，部署后集群内使用 IP:Port 可达（根据实际情况修改）
SERVICE_CIDR="10.254.0.0/16"

# 集群 DNS 域名（根据实际情况修改）
CLUSTER_DNS_DOMAIN="cluster.local."

# NodePort 的端口范围（根据实际情况修改）
NODE_PORT_RANGE="8000-9000"

# 证书及相关二进制文件路径（根据实际情况修改）
#PACKAGE_DIR=/opt/sumscope/package
K8SBIN_DIR=/opt/sumscope/k8s_bin
TMP_SSL=/opt/sumscope/ssl
ETCD_DIR=/opt/sumscope/etcd
SSL_DIR=/etc/kubernetes/ssl
KUBELET_DIR=/opt/sumscope/kubelet
KUBEPROXY_DIR=/opt/sumscope/kube-proxy
DOCKER_DIR=/opt/sumscope/docker-data

# kubelet 初始化镜像，可配置成私有仓库镜像
pod_infra_container_image="registry.access.redhat.com/rhel7/pod-infrastructure:latest"

###########################################################################################
###############################以下变量一般不做修改###########################################
###########################################################################################

#flanneld 网络配置前缀
FLANNEL_ETCD_PREFIX="/kubernetes/network"

#k8s需要生成的token值
BOOTSTRAP_TOKEN=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')

#其他环境变量
MSIPS=`echo $MASTER_IPS |tr -s "," " "`
NDIPS=`echo $NODE_IPS |tr -s "," " "`
ETCDIPS=`echo $ETCD_IPS |tr -s "," " "`
ETCD1=`echo $ETCD_IPS |tr -s "," " "|awk -F" " '{print $1}'`
ETCD2=`echo $ETCD_IPS |tr -s "," " "|awk -F" " '{print $2}'`
ETCD3=`echo $ETCD_IPS |tr -s "," " "|awk -F" " '{print $3}'`
ETCD_NODES="etcd-host0=https://$ETCD1:2380,etcd-host1=https://$ETCD2:2380,etcd-host2=https://$ETCD3:2380"
ETCD_ENDPOINTS="https://$ETCD1:2379,https://$ETCD2:2379,https://$ETCD3:2379"

###########################################################################################
#####################################以下为脚本部分##########################################
###########################################################################################
#安装前的检查
Pre_Check(){
KERNEL=`uname -a|awk -F" " '{ print $3 }'`
FTYPE=`xfs_info /opt/sumscope/ |grep ftype |awk -F"=" '{ print $NF }'`
if [ $FTYPE != '1' ];then
    echo -e "\033[31mfile system check failed,please check!\033[0m"
    exit 0
else
    echo -e "\033[32mfile system d_type check ok!\033[0m"
fi

while true
do
    echo -e "kernel is \033[34m$KERNEL\033[0m,k8s cluster need kernel more than 4.x "
    read -p "are you sure to continue? y/n:" k
        if [ $k = "y" ]; then
            echo -e "\033[32mcontinue to install k8s cluster\033[0m"
            break
        elif [ $k = "n" ];then
            exit 0
        else
            continue
        fi
done

NUM=`rpm -qa |grep libseccomp|wc -l`
rpm -qa |grep libseccomp
if  [ $? = 0 ] && [ $NUM = 2 ];then
    echo -e "\033[32mlibseccomp is already installed,check ok\033[0m"
else
    echo -e "\033[31mlibseccomp and libseccomp-devel not install ,please install by your self\033[0m"
    exit 0
fi
}

#配置服务器单向信任
Pressh(){
echo -e "\033[32mNOW deploy ssh trust,please send your password According to the prompt........\033[0m"
sleep 5
rm -rf ~/.ssh
ssh-keygen -t rsa -f ~/.ssh/id_rsa -P ''
for i in `echo localhost $MSIPS $NDIPS $ETCDIPS|awk '{for(i=1;i<=NF;i++)a[$i,NR]++}{for(j in a){split(j,b,SUBSEP);if(b[2]==NR)printf b[1]" "} printf "\n"}'`;do
        ssh-copy-id -i ~/.ssh/id_rsa.pub root@$i
done
}

#安装前的准备创建目录生成环境变量
Preinstall(){
echo -e "\033[32mADD TO K8S BIN_PATH........\033[0m"
sleep 5
for i in $MSIPS $NDIPS;do
    ssh $i mkdir -p $K8SBIN_DIR $TMP_SSL $SSL_DIR $DOCKER_DIR
    ssh $i swapoff -a
done

for i in $MSIPS $NDIPS;do
   ssh $i "grep -q $K8SBIN_DIR /etc/profile || echo "export PATH=${K8SBIN_DIR}:'\$PATH'" >> /etc/profile"
done
}

#安装cfssl用以生成证书
Install_Cfssl(){
echo -e "\033[32mNOW INSTALL CFSSL........\033[0m"
sleep 5
wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
chmod +x ./cfssl_linux-amd64
mv ./cfssl_linux-amd64 $K8SBIN_DIR/cfssl
chmod +x ./cfssljson_linux-amd64
mv ./cfssljson_linux-amd64 $K8SBIN_DIR/cfssljson
chmod +x ./cfssl-certinfo_linux-amd64
mv ./cfssl-certinfo_linux-amd64 $K8SBIN_DIR/cfssl-certinfo
}

#创建CA证书
Create_Ca_Certificate(){
echo -e "\033[32mNOW CREATE CA CERTS........\033[0m"
sleep 5
cfssl print-defaults config > $TMP_SSL/config.json
cfssl print-defaults csr > $TMP_SSL/csr.json
cat > $TMP_SSL/ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "87600h"
      }
    }
  }
}
EOF

cat > $TMP_SSL/ca-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShangHai",
      "L": "ShangHai",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF
cfssl gencert -initca $TMP_SSL/ca-csr.json | cfssljson -bare $TMP_SSL/ca
for ip in $MSIPS $NDIPS;do
	rsync  -avzP $TMP_SSL/ca* ${ip}:$SSL_DIR
done
}

#创建ETCD证书
Create_Etcd_Certificate(){
echo -e "\033[32mNOW CREATE ETCD CERTS........\033[0m"
sleep 5
cat > $TMP_SSL/etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShangHai",
      "L": "ShangHai",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

for x in $ETCDIPS;do
    sed -i '/"127.0.0.1"/i\    "'$x'",' $TMP_SSL/etcd-csr.json
done

cfssl gencert -ca=$SSL_DIR/ca.pem \
  -ca-key=$SSL_DIR/ca-key.pem \
  -config=$SSL_DIR/ca-config.json \
  -profile=kubernetes $TMP_SSL/etcd-csr.json | cfssljson -bare $TMP_SSL/etcd
#cp ./etcd*.pem $SSL_DIR
for etcdip in $ETCDIPS ;do
	rsync  -avzP $TMP_SSL/etcd*.pem ${etcdip}:$SSL_DIR;
done
}

#创建admin证书
Create_Admin_Certificate(){
echo -e "\033[32mNOW CREATE ADMIN CERTS........\033[0m"
sleep 5
cat > $TMP_SSL/admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShangHai",
      "L": "ShangHai",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF
cfssl gencert -ca=$SSL_DIR/ca.pem \
  -ca-key=$SSL_DIR/ca-key.pem \
  -config=$SSL_DIR/ca-config.json \
  -profile=kubernetes $TMP_SSL/admin-csr.json | cfssljson -bare $TMP_SSL/admin

for masterip in $MSIPS;do
	rsync  -avzP $TMP_SSL/admin*.pem ${masterip}:$SSL_DIR
done
}

#创建flanneld证书
Create_Flanneld_Certificate(){
echo -e "\033[32mNOW CREATE FLANNELD CERTS........\033[0m"
sleep 5
cat > $TMP_SSL/flanneld-csr.json <<EOF
{
  "CN": "flanneld",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShangHai",
      "L": "ShangHai",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

cfssl gencert -ca=$SSL_DIR/ca.pem \
  -ca-key=$SSL_DIR/ca-key.pem \
  -config=$SSL_DIR/ca-config.json \
  -profile=kubernetes $TMP_SSL/flanneld-csr.json | cfssljson -bare $TMP_SSL/flanneld

for flannelip in $MSIPS $NDIPS;do
	rsync  -avzP $TMP_SSL/flanneld*.pem ${flannelip}:$SSL_DIR
done
}


#创建kubernetes证书
Create_Kubernetes_Certificate(){
echo -e "\033[32mNOW CREATE KUBERNETES CERTS........\033[0m"
sleep 5
cat > $TMP_SSL/kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShangHai",
      "L": "ShangHai",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

for y in `echo $MSIPS $NDIPS $CLUSTER_VIP $CLUSTER_KUBERNETES_SVC_IP \
|awk '{for(i=1;i<=NF;i++)a[$i,NR]++}{for(j in a){split(j,b,SUBSEP);if(b[2]==NR)printf b[1]" "} printf "\n"}'`;do
    sed -i '/"127.0.0.1"/a\    "'$y'",' $TMP_SSL/kubernetes-csr.json
done

cfssl gencert -ca=$SSL_DIR/ca.pem \
  -ca-key=$SSL_DIR/ca-key.pem \
  -config=$SSL_DIR/ca-config.json \
  -profile=kubernetes $TMP_SSL/kubernetes-csr.json | cfssljson -bare $TMP_SSL/kubernetes

for kubernetesip in $MSIPS ;do
	rsync  -avzP $TMP_SSL/kubernetes*.pem ${kubernetesip}:$SSL_DIR
done
}

#创建kube-proxy证书
Create_Kubeproxy_Certificate(){
echo -e "\033[32mNOW CREATE KUBE-PROXY CERTS........\033[0m"
sleep 5
cat > $TMP_SSL/kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShangHai",
      "L": "ShangHai",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

cfssl gencert -ca=$SSL_DIR/ca.pem \
  -ca-key=$SSL_DIR/ca-key.pem \
  -config=$SSL_DIR/ca-config.json \
  -profile=kubernetes  $TMP_SSL/kube-proxy-csr.json | cfssljson -bare $TMP_SSL/kube-proxy

for kubepoxyip in $MSIPS $NDIPS;do
	rsync  -avzP $TMP_SSL/kube-proxy*.pem ${kubepoxyip}:$SSL_DIR
done
}


#创建token.csv文件
Create_Token(){
echo -e "\033[32mNOW CREATE TOKEN.CSV........\033[0m"
sleep 5
if [ -f /etc/kubernetes/token.csv ];then
    echo -e "\033[31mtoken.csv is exits,please check\033[0m"
        while true
        do
        read -p "delete token to recreate it ,Input y/n:" token
            if  [ $token = "y" ]
            then
                rm -f /etc/kubernetes/token.csv
                cat > token.csv <<EOF
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF
                for tokeip in $MSIPS $NDIPS;do
                    rsync  -avzP token.csv ${tokeip}:/etc/kubernetes/
                done
                break
            elif
                [ $token = "n" ]
            then
                break
            else
                echo "please input y/n....."
            fi
        done
else
    cat > token.csv <<EOF
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF
for tokeip in $MSIPS $NDIPS;do
	rsync  -avzP token.csv ${tokeip}:/etc/kubernetes/
done
fi
}


Install_Etcd(){
echo -e "\033[32mNOW INSTALL ETCD SERVICE........\033[0m"
sleep 5
for z in $ETCDIPS;do
    ssh $z mkdir -p $ETCD_DIR
done

cat > etcd.service <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
WorkingDirectory=$ETCD_DIR
ExecStart=$K8SBIN_DIR/etcd \\
  --name=NODE_NAME \\
  --cert-file=$SSL_DIR/etcd.pem \\
  --key-file=$SSL_DIR/etcd-key.pem \\
  --peer-cert-file=$SSL_DIR/etcd.pem \\
  --peer-key-file=$SSL_DIR/etcd-key.pem \\
  --trusted-ca-file=$SSL_DIR/ca.pem \\
  --peer-trusted-ca-file=$SSL_DIR/ca.pem \\
  --initial-advertise-peer-urls=https://NODE_IP:2380 \\
  --listen-peer-urls=https://NODE_IP:2380 \\
  --listen-client-urls=https://NODE_IP:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://NODE_IP:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=${ETCD_NODES} \\
  --initial-cluster-state=new \\
  --data-dir=$ETCD_DIR
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

for etcdips in $ETCDIPS ;do
	rsync  -avzP etcd.service ${etcdips}:/etc/systemd/system/;
done

ssh $ETCD1 sed -i 's#NODE_NAME#etcd-host0#' /etc/systemd/system/etcd.service
ssh $ETCD2 sed -i 's#NODE_NAME#etcd-host1#' /etc/systemd/system/etcd.service
ssh $ETCD3 sed -i 's#NODE_NAME#etcd-host2#' /etc/systemd/system/etcd.service
ssh $ETCD1 sed -i 's#NODE_IP#'$ETCD1'#' /etc/systemd/system/etcd.service
ssh $ETCD2 sed -i 's#NODE_IP#'$ETCD2'#' /etc/systemd/system/etcd.service
ssh $ETCD3 sed -i 's#NODE_IP#'$ETCD3'#' /etc/systemd/system/etcd.service

for etcdips2 in $ETCDIPS ;do
    rsync  -avzP  $PWD/bin/etcd* ${etcdips2}:$K8SBIN_DIR
    ssh $etcdips2  'systemctl daemon-reload && systemctl enable etcd'
done

for etcdips3 in $ETCDIPS;do
    ssh $etcdips3  "systemctl start etcd" &
done
wait
}

Install_Flanneld(){
echo -e "\033[32mNOW INSTALL FLANNELD SERVICE........\033[0m"
sleep 15
NUM=`for ip in ${ETCDIPS}; do
  ETCDCTL_API=3 $K8SBIN_DIR/etcdctl \
  --endpoints=https://${ip}:2379  \
  --cacert=$SSL_DIR/ca.pem \
  --cert=$SSL_DIR/etcd.pem \
  --key=$SSL_DIR/etcd-key.pem \
  endpoint health; done|grep "is healthy"|wc -l`

if [ $NUM==3 ];then
sleep 10
$K8SBIN_DIR/etcdctl \
--endpoints=${ETCD_ENDPOINTS} \
--ca-file=${SSL_DIR}/ca.pem \
--cert-file=${SSL_DIR}/flanneld.pem \
--key-file=${SSL_DIR}/flanneld-key.pem \
set ${FLANNEL_ETCD_PREFIX}/config '{"Network":"'${CLUSTER_CIDR}'", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}'
else
    echo "\033[31mEtcd Start Failed ,Please Check\033[0m"
    exit 0
fi

cat > flanneld.service << EOF
[Unit]
Description=Flanneld overlay address etcd agent
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service

[Service]
Type=notify
ExecStart=$K8SBIN_DIR/flanneld \\
  -etcd-cafile=$SSL_DIR/ca.pem \\
  -etcd-certfile=$SSL_DIR/flanneld.pem \\
  -etcd-keyfile=$SSL_DIR/flanneld-key.pem \\
  -etcd-endpoints=${ETCD_ENDPOINTS} \\
  -etcd-prefix=${FLANNEL_ETCD_PREFIX}
ExecStartPost=$K8SBIN_DIR/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=on-failure

[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
EOF

for flannelips in `echo $MSIPS $NDIPS |awk '{for(i=1;i<=NF;i++)a[$i,NR]++}{for(j in a){split(j,b,SUBSEP);if(b[2]==NR)printf b[1]" "} printf "\n"}'`
do
    rsync  -avzP $PWD/bin/{flanneld,mk-docker-opts.sh} ${flannelips}:$K8SBIN_DIR
	rsync  -avzP flanneld.service  ${flannelips}:/etc/systemd/system/
	ssh $flannelips  'systemctl daemon-reload && systemctl enable etcd && systemctl start flanneld.service'
done
}

Check(){
echo -e "\033[32mNOW CHECK ETCD AND FLANNELD........\033[0m"
sleep 5
for ip in ${ETCDIPS}; do
  ETCDCTL_API=3 $K8SBIN_DIR/etcdctl \
  --endpoints=https://${ip}:2379  \
  --cacert=$SSL_DIR/ca.pem \
  --cert=$SSL_DIR/etcd.pem \
  --key=$SSL_DIR/etcd-key.pem \
  endpoint health; done

$K8SBIN_DIR/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=$SSL_DIR/ca.pem \
  --cert-file=$SSL_DIR/flanneld.pem \
  --key-file=$SSL_DIR/flanneld-key.pem \
  get ${FLANNEL_ETCD_PREFIX}/config

$K8SBIN_DIR/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=$SSL_DIR/ca.pem \
  --cert-file=$SSL_DIR/flanneld.pem \
  --key-file=$SSL_DIR/flanneld-key.pem \
  ls ${FLANNEL_ETCD_PREFIX}/subnets

$K8SBIN_DIR/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=$SSL_DIR/ca.pem \
  --cert-file=$SSL_DIR/flanneld.pem \
  --key-file=$SSL_DIR/flanneld-key.pem \
  ls ${FLANNEL_ETCD_PREFIX}/subnets
}

Install_Apiserver(){
echo -e "\033[32mNOW INSTALL KUBE-APISERVER........\033[0m"
sleep 5
for bb in $MSIPS;do
cat  > $bb <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
ExecStart=$K8SBIN_DIR/kube-apiserver \\
  --admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --advertise-address=${bb} \\
  --bind-address=${bb} \\
  --insecure-bind-address=${bb} \\
  --authorization-mode=RBAC,Node \\
  --runtime-config=rbac.authorization.k8s.io/v1beta1 \\
  --kubelet-https=true \\
  --token-auth-file=/etc/kubernetes/token.csv \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --service-node-port-range=${NODE_PORT_RANGE} \\
  --tls-cert-file=$SSL_DIR/kubernetes.pem \\
  --tls-private-key-file=$SSL_DIR/kubernetes-key.pem \\
  --client-ca-file=$SSL_DIR/ca.pem \\
  --service-account-key-file=$SSL_DIR/ca-key.pem \\
  --etcd-cafile=$SSL_DIR/ca.pem \\
  --etcd-certfile=$SSL_DIR/kubernetes.pem \\
  --etcd-keyfile=$SSL_DIR/kubernetes-key.pem \\
  --etcd-servers=${ETCD_ENDPOINTS} \\
  --enable-swagger-ui=true \\
  --allow-privileged=true \\
  --apiserver-count=2 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/lib/audit.log \\
  --event-ttl=1h \\
  --v=2
Restart=on-failure
RestartSec=5
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
done

for x in $MSIPS;do
    for i in `ls`;do
        if [ $i = $x ];then
            rsync -avzP $i $x:/etc/systemd/system/kube-apiserver.service
        else
            continue
        fi
    done
done

for masterip in $MSIPS ;do
    rsync  -avzP  $PWD/bin/kube-apiserver ${masterip}:$K8SBIN_DIR
    ssh $masterip  'systemctl daemon-reload && systemctl enable kube-apiserver && systemctl start kube-apiserver'
done
rm -f $MSIPS
}

Install_ControllerManager(){
echo -e "\033[32mNOW INSTALL KUBE-CONTROLLER-MANAGER........\033[0m"
sleep 5
cat > kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=$K8SBIN_DIR/kube-controller-manager \\
  --address=127.0.0.1 \\
  --master=http://$CLUSTER_VIP:$HTTP_HAPROXY_PORT \\
  --allocate-node-cidrs=true \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --cluster-cidr=${CLUSTER_CIDR} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=$SSL_DIR/ca.pem \\
  --cluster-signing-key-file=$SSL_DIR/ca-key.pem \\
  --service-account-private-key-file=$SSL_DIR/ca-key.pem \\
  --root-ca-file=$SSL_DIR/ca.pem \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

for masterip in $MSIPS ;do
    rsync  -avzP  $PWD/bin/kube-controller-manager ${masterip}:$K8SBIN_DIR
    rsync  -avzP  kube-controller-manager.service ${masterip}:/etc/systemd/system/
    ssh $masterip  'systemctl daemon-reload && systemctl enable kube-controller-manager && systemctl start kube-controller-manager'
done
}

Install_KubeScheduler(){
echo -e "\033[32mNOW INSTALL KUBE-SCHEDULER........\033[0m"
sleep 5
cat > kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=$K8SBIN_DIR/kube-scheduler \\
  --address=127.0.0.1 \\
  --master=http://$CLUSTER_VIP:$HTTP_HAPROXY_PORT \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

for masterip in $MSIPS ;do
    rsync  -avzP $PWD/bin/kube-scheduler ${masterip}:$K8SBIN_DIR
    rsync  -avzP kube-scheduler.service  ${masterip}:/etc/systemd/system/
    ssh $masterip  'systemctl daemon-reload && systemctl enable kube-scheduler && systemctl start kube-scheduler'
done
}

Install_Kubectl(){
echo -e "\033[32mNOW INSTALL KUBECTL........\033[0m"
sleep 5
for masterip in $MSIPS ;do
    rsync  -avzP $PWD/bin/kubectl ${masterip}:$K8SBIN_DIR
done

kubectl config set-cluster kubernetes \
  --certificate-authority=$SSL_DIR/ca.pem \
  --embed-certs=true \
  --server="https://${CLUSTER_VIP}:${HTTPS_HAPROXY_PORT}"
kubectl config set-credentials admin \
  --client-certificate=$SSL_DIR/admin.pem \
  --embed-certs=true \
  --client-key=$SSL_DIR/admin-key.pem
kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin
kubectl config use-context kubernetes
kubectl get componentstatuses
}

Install_Kubelet(){
echo -e "\033[32mNOW INSTALL KUBELET........\033[0m"
sleep 5
kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap
kubectl config set-cluster kubernetes \
  --certificate-authority=$SSL_DIR/ca.pem \
  --embed-certs=true \
  --server="https://${CLUSTER_VIP}:${HTTPS_HAPROXY_PORT}" \
  --kubeconfig=bootstrap.kubeconfig
kubectl config set-credentials kubelet-bootstrap \
  --token=`cat /etc/kubernetes/token.csv |awk -F"," '{print $1}'` \
  --kubeconfig=bootstrap.kubeconfig
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=bootstrap.kubeconfig
kubectl config use-context default --kubeconfig=bootstrap.kubeconfig

for i in $NDIPS;do
cat > $i <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=$KUBELET_DIR
ExecStart=$K8SBIN_DIR/kubelet \\
  --address=$i \\
  --hostname-override=$i \\
  --pod-infra-container-image=$pod_infra_container_image \\
  --bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \\
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \\
  --cert-dir=$SSL_DIR \\
  --cluster-dns=$CLUSTER_DNS_SVC_IP \\
  --cluster-domain=$CLUSTER_DNS_DOMAIN \\
  --hairpin-mode promiscuous-bridge \\
  --allow-privileged=true \\
  --serialize-image-pulls=false \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
done

for x in $NDIPS;do
    for i in `ls`;do
        if [ $i = $x ];then
            rsync -avzP $i $x:/etc/systemd/system/kubelet.service
        else
            continue
        fi
    done
done
rm -f $NDIPS

for i in $NDIPS;do
    ssh $i mkdir -p $KUBELET_DIR
    rsync  -avzP $PWD/bin/kubelet ${i}:$K8SBIN_DIR
    rsync  -avzP bootstrap.kubeconfig   ${i}:/etc/kubernetes/
    ssh $i  'systemctl daemon-reload && systemctl enable kubelet && systemctl start kubelet'
done
echo -e "\033[32mNOW APPROVE NODE TO CLUSTER........\033[0m"
sleep 5
for i in `kubectl get csr|awk '{ print $1 }' |grep -v NAME`;do kubectl certificate approve $i;done
kubectl get csr
}

Install_Kubeproxy(){
echo -e "\033[32mNOW INSTALL KUBE-PROXY........\033[0m"
sleep 5
kubectl config set-cluster kubernetes \
  --certificate-authority=$SSL_DIR/ca.pem \
  --embed-certs=true \
  --server="https://${CLUSTER_VIP}:${HTTPS_HAPROXY_PORT}" \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config set-credentials kube-proxy \
  --client-certificate=$SSL_DIR/kube-proxy.pem \
  --client-key=$SSL_DIR/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

for i in $NDIPS;do
cat > $i <<EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
WorkingDirectory=$KUBEPROXY_DIR
ExecStart=$K8SBIN_DIR/kube-proxy \\
  --bind-address=$i \\
  --hostname-override=$i \\
  --cluster-cidr=${CLUSTER_CIDR} \\
  --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
done

for x in $NDIPS;do
    for i in `ls`;do
        if [ $i = $x ];then
            rsync -avzP $i $x:/etc/systemd/system/kube-proxy.service
        else
            continue
        fi
    done
done
rm -f $NDIPS

for i in $NDIPS;do
    ssh $i mkdir -p $KUBEPROXY_DIR
    rsync  -avzP $PWD/bin/kube-proxy ${i}:$K8SBIN_DIR
    rsync  -avzP kube-proxy.kubeconfig ${i}:/etc/kubernetes/
    ssh $i  'systemctl daemon-reload && systemctl enable kube-proxy && systemctl start kube-proxy'
done
}

Install_docker(){
for i in `echo $MSIPS $NDIPS |awk '{for(i=1;i<=NF;i++)a[$i,NR]++}{for(j in a){split(j,b,SUBSEP);if(b[2]==NR)printf b[1]" "} printf "\n"}'`
do
    yum remove -y docker docker-common docker-selinux docker-engine
    yum install -y yum-utils device-mapper-persistent-data lvm2
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum-config-manager --disable docker-ce-edge
    yum install -y docker-ce
    sed -i 's/ExecStart=\/usr\/bin\/dockerd/ExecStart=\/usr\/bin\/dockerd \$DOCKER_NETWORK_OPTIONS/' /usr/lib/systemd/system/docker.service
    sed -i '/ExecStart=\/usr\/bin\/dockerd \$DOCKER_NETWORK_OPTIONS/i\EnvironmentFile=-/run/flannel/docker' /usr/lib/systemd/system/docker.service
done

cat <<EOF >  /etc/docker/daemon.json
{
  "storage-driver": "overlay2",
  "graph": "$DOCKER_DIR"
}
EOF
for i in $MSIPS $NDIPS;do
    rsync  -avzP /etc/docker/daemon.json $i:/etc/docker
done

for i in $MSIPS $NDIPS;do
    systemctl enable docker
    systemctl start docker
done
}

Restore(){
while true
do
    read -p "delete all directory ,files and data,are you sure !? Please Input y/n:" kk
        if [ $kk = "y" ]; then
            for i  in $MSIPS;do
                ssh $i 'systemctl stop kube-apiserver && systemctl stop kube-scheduler && systemctl stop kube-controller-manager && systemctl stop flanneld && systemctl stop docker'
            done
            for i in $NDIPS;do
                ssh $i 'systemctl stop kubelet && systemctl stop flanneld && systemctl stop kube-proxy && systemctl stop docker'
            done
            for i in $ETCDIPS;do
                ssh $i systemctl stop etcd
            done
            for i in $MSIPS $NDIPS;do
                ssh $i         rm -rf /opt/sumscope/{etcd,k8s_bin,package,ssl,kubelet,kube-proxy,docker-data} \
                /etc/systemd/system/{kube-controller-manager.service,kube-apiserver.service,kube-scheduler.service,etcd.service,flanneld.service,kubelet.service,kube-proxy.service} /etc/kubernetes/
            done
            break
        elif [ $kk = "n" ];then
            break
        else
            echo "please input y/n....."
        fi
done
}

Help(){
echo -e "1. Usage: \033[32m-i\033[0m (install all the k8s cluster)."
echo -e "2. Usage: \033[32m-r\033[0m (stop all the k8s process with 'systemctl stop' and delete all related to k8s)."
echo -e "3. Usage: \033[32m-h\033[0m (help to use k8s_install.sh."
}

Install_all(){
Pre_Check
Pressh
Preinstall
Install_Cfssl
source /etc/profile
Create_Token
Create_Ca_Certificate
Create_Etcd_Certificate
Create_Admin_Certificate
Create_Flanneld_Certificate
Create_Kubernetes_Certificate
Create_Kubeproxy_Certificate
Install_Etcd
Install_Flanneld
Check
Install_docker
Install_Apiserver
Install_ControllerManager
Install_KubeScheduler
Install_Kubectl
Install_Kubelet
Install_Kubeproxy
}

case $1 in
	""  )
	    Help
        ;;
	-h )
	    Help
        ;;
	-i )
        Install_all
        ;;
	-r )
	    Restore
esac
