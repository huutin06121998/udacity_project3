# Instructions for developers

## deployment process

### dockerfile local check  
```sh
export CONTAINER_NAME=udacity_project3
export CONTAINER_TAG=1.0.1
```
#### check building of the docker file
```sh
docker build . -f Dockerfile --tag $CONTAINER_NAME:$CONTAINER_TAG
```
#### check built up docker file
```sh
docker run --entrypoint="" -it $CONTAINER_NAME:$CONTAINER_TAG  /bin/sh
```

### create AWS infrastructure 
```sh
export AWS_ECR_REPO_NAME=udacity-project3-eks

export ROLE_CODEBUILD=aws-codebuild-ecr-push
export ROLE_CODEBUILD_POLICY=aws-codebuild-ecr-push-policy
export CODEBUILD_PROJECT_NAME=aws-dockerbuild-coworkingspace
export CODEBUILD_GITHUB_REPO_URL="https://github.com/cherkavi/udacity-aws-devops-eks"
export AWS_S3_CODEBUILD_LOGS="${CODEBUILD_PROJECT_NAME}-s3-logs2"

export ROLE_EKS_CLUSTER=aws-eks-cluster
export ROLE_EKS_NODEGROUP=aws-eks-nodegroup

export HELM_BITNAMI_REPO=bitnami-repo

export K8S_SERVICE_POSTGRESQL=service-coworking-postgresql

export K8S_APP_SECRET_NAME=udacity-db-credentials
export K8S_APP_CONFIG=udacity-project3-config
export K8S_DEPLOYMENT_NAME=udacity_project3
export BUILD_VERSION=1.0.5
```

#### ECR: Elastic Container Registry
[init variables](#create-aws-infrastructure)
*create*
```sh
aws ecr create-repository  --repository-name $AWS_ECR_REPO_NAME
```
*check*
```sh
# list of all repositories 
aws ecr describe-repositories 

# list of all images in repository
aws ecr list-images  --repository-name $AWS_ECR_REPO_NAME
```
*delete*
```sh
aws ecr delete-repository  --repository-name $AWS_ECR_REPO_NAME
```


#### CodeBuild
##### CodeBuild role
[init variables](#create-aws-infrastructure)
*create*
```sh
aws iam create-role --role-name $ROLE_CODEBUILD --assume-role-policy-document file://codebuild-iam-role.json
aws iam put-role-policy --role-name $ROLE_CODEBUILD --policy-name $ROLE_CODEBUILD_POLICY --policy-document file://codebuild-iam-policy.json
```
*check*
```sh
aws iam get-role --role-name $ROLE_CODEBUILD
aws iam get-role-policy --role-name $ROLE_CODEBUILD --policy-name $ROLE_CODEBUILD_POLICY
```
*delete*
```sh
# echo "delete role: " $ROLE_CODEBUILD " with policy: " $ROLE_CODEBUILD_POLICY
# aws iam delete-role-policy --role-name $ROLE_CODEBUILD --policy-name $ROLE_CODEBUILD_POLICY
# aws iam delete-role --role-name $ROLE_CODEBUILD
```

##### CodeBuild S3 bucket for logs
[init variables](#create-aws-infrastructure)
*create*
```sh
aws s3 mb s3://$AWS_S3_CODEBUILD_LOGS
```
*check*
```sh
aws s3 ls
aws s3 ls --recursive s3://$AWS_S3_CODEBUILD_LOGS
# aws s3api get-object --bucket $AWS_S3_CODEBUILD_LOGS --key 63a94d38-45f1-4b3f-9a22-f3bebf1a1650.gz 63a94d38-45f1-4b3f-9a22-f3bebf1a1650.gz
```
*delete*
```sh
# echo "remove bucket: ${AWS_S3_CODEBUILD_LOGS}
# aws s3 rb s3://$AWS_S3_CODEBUILD_LOGS
```

##### CodeBuild project
[init variables](#create-aws-infrastructure)
*create*
```sh
ROLE_CODEBUILD_IAM=`aws iam get-role --role-name  $ROLE_CODEBUILD --output text --query 'Role.Arn'`
echo $ROLE_CODEBUILD_IAM

# create codebuild-project.json document from template 
sed "s|<GITHUB_REPO_URL>|$CODEBUILD_GITHUB_REPO_URL|" codebuild-project-template.json > codebuild-project.json
sed --in-place "s|<AWS_ROLE_IAM>|$ROLE_CODEBUILD_IAM|" codebuild-project.json
sed --in-place "s|<PROJECT_NAME>|$CODEBUILD_PROJECT_NAME|" codebuild-project.json
sed --in-place "s|<AWS_ECR_REPOSITORY_NAME>|$AWS_ECR_REPO_NAME|" codebuild-project.json
sed --in-place "s|<AWS_S3_CODEBUILD_LOGS>|$AWS_S3_CODEBUILD_LOGS|" codebuild-project.json

aws codebuild create-project --cli-input-json file://codebuild-project.json
```
*check*
```sh
aws codebuild batch-get-projects --names $CODEBUILD_PROJECT_NAME
aws codebuild list-projects 
```
*delete*
```sh
# echo "delete project by name: "$CODEBUILD_PROJECT_NAME
# aws codebuild delete-project --name $CODEBUILD_PROJECT_NAME
```

#### EKS
[init variables](#create-aws-infrastructure)
##### EKS Cluster
*role for cluster create*
```sh
# create role
aws iam create-role --role-name $ROLE_EKS_CLUSTER --assume-role-policy-document file://eks-iam-role.json
# attach policies
for POLICY_NAME in AmazonEKSClusterPolicy; do
    POLICY_ARN=`aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" | jq -r .[]`
    echo "attach to role:"$POLICY_ARN
    aws iam attach-role-policy --role-name $ROLE_EKS_CLUSTER --policy-arn $POLICY_ARN
done
```
*role for cluster check*
```sh
# list attached policies to role
aws iam list-attached-role-policies --role-name $ROLE_EKS_CLUSTER --query 'AttachedPolicies[].PolicyArn' --output json
```
*role for cluster delete*
```sh
echo "delete role: " $ROLE_EKS_CLUSTER
for POLICY_NAME in `aws iam list-attached-role-policies --role-name $ROLE_EKS_CLUSTER --query 'AttachedPolicies[].PolicyArn' --output json | jq -r .[]`; do
    echo "detach policy: $POLICY_NAME"
    aws iam detach-role-policy --role-name $ROLE_EKS_CLUSTER --policy-arn $POLICY_NAME
done
aws iam delete-role --role-name $ROLE_EKS_CLUSTER
```

##### EKS Node Group
[init variables](#create-aws-infrastructure)
*role for node group create*
```sh
# create role
aws iam create-role --role-name $ROLE_EKS_NODEGROUP --assume-role-policy-document file://eks-node-iam-role.json
# attach policies
for POLICY_NAME in AmazonEKSWorkerNodePolicy AmazonEC2ContainerRegistryReadOnly AmazonEKS_CNI_Policy AmazonEMRReadOnlyAccessPolicy_v2 AmazonEBSCSIDriverPolicy; do
    POLICY_ARN=`aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" | jq -r .[]`
    echo "attach policy to role:"$POLICY_ARN
    aws iam attach-role-policy --role-name $ROLE_EKS_NODEGROUP --policy-arn $POLICY_ARN
done
```
*role for node group check*
```sh
# list attached policies to role
aws iam get-role --role-name $ROLE_EKS_NODEGROUP
aws iam list-attached-role-policies --role-name $ROLE_EKS_NODEGROUP --query 'AttachedPolicies[].PolicyArn' --output json
```
*role for node group delete*
```sh
echo "delete role: " $ROLE_EKS_NODEGROUP
for POLICY_NAME in `aws iam list-attached-role-policies --role-name $ROLE_EKS_NODEGROUP --query 'AttachedPolicies[].PolicyArn' --output json | jq -r .[]`; do
    echo "detach policy: $POLICY_NAME"
    aws iam detach-role-policy --role-name $ROLE_EKS_NODEGROUP --policy-arn $POLICY_NAME
done
aws iam delete-role --role-name $ROLE_EKS_NODEGROUP
```

*create cluster manually*
```sh
echo "create EKS cluster "
x-www-browser https://${AWS_REGION}.console.aws.amazon.com/eks

echo "add EKS.NodeGroup with role: ${ROLE_EKS_NODEGROUP}"
CLUSTER_NAME=`aws eks list-clusters | jq -r .clusters[] | head -n 1`
x-www-browser https://${AWS_REGION}.console.aws.amazon.com/eks/home?region=${AWS_REGION}#/clusters/${CLUSTER_NAME}/add-node-group 

# check cluster
aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" 
kubectl get pods -n kube-system
```

##### kubectl login
[init variables](#create-aws-infrastructure)
```sh
CLUSTER_NAME=`aws eks list-clusters | jq -r .clusters[] | head -n 1`
echo $CLUSTER_NAME
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
```

##### install cloudwatch agent
[init variables](#create-aws-infrastructure)
```sh
CLUSTER_NAME=`aws eks list-clusters | jq -r .clusters[] | head -n 1`
echo $CLUSTER_NAME

ClusterName=$CLUSTER_NAME
RegionName=$AWS_REGION
FluentBitHttpPort='2020'
FluentBitReadFromHead='Off'
FluentBitReadFromTail='On'
FluentBitHttpServer='On'
curl https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml | sed 's/{{cluster_name}}/'${ClusterName}'/;s/{{region_name}}/'${RegionName}'/;s/{{http_server_toggle}}/"'${FluentBitHttpServer}'"/;s/{{http_server_port}}/"'${FluentBitHttpPort}'"/;s/{{read_from_head}}/"'${FluentBitReadFromHead}'"/;s/{{read_from_tail}}/"'${FluentBitReadFromTail}'"/' | kubectl apply -f -

kubectl get pods -n amazon-cloudwatch
# cloudwatch-agent 
# fluent-bit

# cloud watch check log ouptut for container
x-www-browser https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#container-insights:infrastructure
```

##### set up a Postgres database with a Helm Chart.
[init variables](#create-aws-infrastructure)
```sh
# setup helm
echo $HELM_BITNAMI_REPO
helm repo add $HELM_BITNAMI_REPO https://charts.bitnami.com/bitnami
# helm repo list
```

workaround for postgresql storage
```sh
# kubectl delete pv local-storage
NODE_1_NAME=` kubectl get nodes -o jsonpath='{.items[*].metadata.name}'  | tr " " "\n" | head -n 1`
echo $NODE_1_NAME
sed "s|<NODE_INSTANCE_NAME>|$NODE_1_NAME|" eks-localstorage.yaml-template | kubectl apply -f -
```

```sh
# install postgresql as a service 
helm install $K8S_SERVICE_POSTGRESQL $HELM_BITNAMI_REPO/postgresql --set global.storageClass=local-storage
helm list
# helm uninstall $K8S_SERVICE_POSTGRESQL

## check installation
kubectl get svc
kubectl get pods
kubectl get pv
kubectl get pvc
# kubectl get events
```

#### connect to PostgreSQL 
[init variables](#create-aws-infrastructure)
##### db port forwarding
```sh
# forward local port 5432 to service 
kubectl port-forward --namespace default svc/$K8S_SERVICE_POSTGRESQL 5432:5432
```
##### db connect 
```sh
# open in another terminal 
export POSTGRES_PASSWORD=$(kubectl get secret --namespace default service-coworking-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)
echo $POSTGRES_PASSWORD
PGPASSWORD="$POSTGRES_PASSWORD" psql --host 127.0.0.1 -U postgres -d postgres -p 5432
```

------------------
## deploy changes 

### build docker image and push it to ECR
#### start build
[!!! init env variables !!!](#create-aws-infrastructure)
```sh
# start build - type parameter is mandatory !!! 
aws codebuild start-build --project-name $CODEBUILD_PROJECT_NAME --environment-variables-override '[{"name":"CONTAINER_TAG","value":"'$BUILD_VERSION'","type":"PLAINTEXT"}]'

## list of builds in project
# aws codebuild list-builds-for-project --project-name $CODEBUILD_PROJECT_NAME
## check one build 
# aws codebuild batch-get-builds --ids aws-dockerbuild-coworkingspace:e8a61490-ce3b-4079-98f6-50db93a3299d
```

#### check logs
```sh
OBJECT_ID=`aws s3 ls --recursive s3://$AWS_S3_CODEBUILD_LOGS | tail -n 1 | awk '{print $4}'`
aws s3api get-object --bucket $AWS_S3_CODEBUILD_LOGS --key $OBJECT_ID $OBJECT_ID
vim $OBJECT_ID
```

#### check generated images with your BUILD_VERSION
```sh
aws ecr list-images  --repository-name $AWS_ECR_REPO_NAME

## docker login 
AWS_ACCOUNT_ID=`aws sts get-caller-identity --query Account | jq -r . `
docker login -u AWS -p $(aws ecr get-login-password --region ${AWS_REGION}) ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

## pull image from repository
aws_ecr_repository_uri=`aws ecr describe-repositories --repository-names $AWS_ECR_REPO_NAME | jq -r '.repositories[0].repositoryUri'`
docker_image_remote_name=$aws_ecr_repository_uri:$BUILD_VERSION
echo $docker_image_remote_name
docker pull  $docker_image_remote_name
```

### EKS application configuration 
[!!! init env variables !!!](#create-aws-infrastructure)
#### EKS secret for app
*create*
```sh
POSTGRES_PASSWORD=$(kubectl get secret --namespace default service-coworking-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)
# echo $POSTGRES_PASSWORD
POSTGRES_USERNAME=postgres
kubectl create secret generic $K8S_APP_SECRET_NAME \
--from-literal=POSTGRES_USERNAME=$POSTGRES_USERNAME \
--from-literal=POSTGRES_PASSWORD=$POSTGRES_PASSWORD
```
*check*
```sh
kubectl get secret $K8S_APP_SECRET_NAME
```
*delete*
```sh
# kubectl delete secret $K8S_APP_SECRET_NAME
```

#### EKS configmap for app
[!!! init env variables !!!](#create-aws-infrastructure)
*create*
```sh
APP_PORT=5153
DB_HOST=$K8S_SERVICE_POSTGRESQL
DB_PORT="5432"
DB_NAME="postgres"
kubectl create configmap $K8S_APP_CONFIG \
--from-literal=APP_PORT=$APP_PORT \
--from-literal=DB_HOST=$DB_HOST \
--from-literal=DB_PORT=$DB_PORT \
--from-literal=DB_NAME=$DB_NAME
```
*check*
```sh
kubectl get configmap $K8S_APP_CONFIG -o json
```
*delete*
```sh
# kubectl delete configmap $K8S_APP_CONFIG
```

### fill up databse with SQL.DDL
[initiate port forwarding](#db-port-forwarding)
```sh
for each_file in `ls db/*`; do
    echo "execute file: $each_file"
    PGPASSWORD="$POSTGRES_PASSWORD" psql --host 127.0.0.1 -U postgres -d postgres -p 5432 -f $each_file
done
```

### deployment to EKS from ECR
[init env variables](#create-aws-infrastructure)  
[kubectl login](#kubectl-login)  
```sh
## deployment
sed "s|<K8S_APP_SECRET_NAME>|$K8S_APP_SECRET_NAME|" eks-deployment-app.yaml-template > eks-deployment-app.yaml
sed --in-place "s|<BUILD_VERSION>|$BUILD_VERSION|" eks-deployment-app.yaml
sed --in-place "s|<K8S_APP_CONFIG>|$K8S_APP_CONFIG|" eks-deployment-app.yaml
sed --in-place "s|<APP_PORT>|$APP_PORT|" eks-deployment-app.yaml
aws_ecr_repository_uri=`aws ecr describe-repositories --repository-names $AWS_ECR_REPO_NAME | jq -r '.repositories[0].repositoryUri'`
docker_image_remote_name=$aws_ecr_repository_uri:$BUILD_VERSION
sed --in-place "s|<DOCKER_IMAGE_URI>|$docker_image_remote_name|" eks-deployment-app.yaml
sed --in-place "s|<K8S_DEPLOYMENT_NAME>|$K8S_DEPLOYMENT_NAME|" eks-deployment-app.yaml

kubectl apply -f eks-deployment-app.yaml
# kubectl delete -f eks-deployment-app.yaml

## service
sed "s|<APP_PORT>|$APP_PORT|" eks-service-app.yaml-template > eks-service-app.yaml
sed --in-place "s|<K8S_DEPLOYMENT_NAME>|$K8S_DEPLOYMENT_NAME|" eks-service-app.yaml
kubectl apply -f eks-service-app.yaml
```
### check deployment 
```sh
kubectl get services
kubectl get service $K8S_DEPLOYMENT_NAME -o yaml
kubectl get deployments
kubectl get pods
```

## redeploy application
1. push your chages 
```sh
git push
```
2. [change version of your application](#create-aws-infrastructure)  
3. [run codebuild](#build-docker-image-and-push-it-to-ecr)
4. check your image or [check logs](#check-logs)
```sh
echo $BUILD_VERSION
aws ecr list-images  --repository-name $AWS_ECR_REPO_NAME | grep $BUILD_VERSION
```
5. [deploy to EKS](#deployment-to-eks-from-ecr)
6. [check new version](#check-deployment )