#!/bin/bash

# Script para auditar todos los recursos principales en AWS
# Uso: ./aws_audit.sh [region]
# Ejemplo: ./aws_audit.sh us-east-1

# Verificar si se proporcionó una región
if [ $# -eq 1 ]; then
    REGION=$1
    echo "🌍 Usando región: $REGION"
    REGION_FLAG="--region $REGION"
else
    echo "🌍 Usando región por defecto del perfil AWS"
    REGION_FLAG=""
fi

echo "🔍 AUDITORIA COMPLETA DE RECURSOS AWS"
echo "====================================="

# COMPUTE RESOURCES
echo -e "\n💻 INSTANCIAS EC2:"
aws ec2 describe-instances $REGION_FLAG --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,PublicIpAddress,VpcId]' --output table

echo -e "\n🖥️ IMAGENES AMI PERSONALIZADAS:"
aws ec2 describe-images $REGION_FLAG --owners self --query 'Images[*].[ImageId,Name,State,CreationDate]' --output table

echo -e "\n📦 VOLUMENES EBS:"
aws ec2 describe-volumes $REGION_FLAG --query 'Volumes[*].[VolumeId,Size,VolumeType,State,Attachments[0].InstanceId]' --output table

echo -e "\n📷 SNAPSHOTS EBS:"
aws ec2 describe-snapshots $REGION_FLAG --owner-ids self --query 'Snapshots[*].[SnapshotId,VolumeSize,State,StartTime,Description]' --output table

# NETWORKING
echo -e "\n🌐 VPCs:"
aws ec2 describe-vpcs $REGION_FLAG --query 'Vpcs[*].[VpcId,State,CidrBlock,IsDefault]' --output table

echo -e "\n🔗 ELASTIC IPS:"
aws ec2 describe-addresses $REGION_FLAG --query 'Addresses[*].[PublicIp,AllocationId,AssociationId,InstanceId]' --output table

echo -e "\n⚖️ LOAD BALANCERS (ALB/NLB):"
aws elbv2 describe-load-balancers $REGION_FLAG --query 'LoadBalancers[*].[LoadBalancerName,Type,State.Code,VpcId]' --output table

echo -e "\n⚖️ LOAD BALANCERS CLASICOS (ELB):"
aws elb describe-load-balancers $REGION_FLAG --query 'LoadBalancerDescriptions[*].[LoadBalancerName,Scheme,VPCId]' --output table

echo -e "\n🌍 NAT GATEWAYS:"
aws ec2 describe-nat-gateways $REGION_FLAG --query 'NatGateways[*].[NatGatewayId,State,VpcId,SubnetId]' --output table

echo -e "\n🌐 INTERNET GATEWAYS:"
aws ec2 describe-internet-gateways $REGION_FLAG --query 'InternetGateways[*].[InternetGatewayId,Attachments[0].VpcId,Attachments[0].State]' --output table

# DATABASES
echo -e "\n🗄️ RDS DATABASES:"
aws rds describe-db-instances $REGION_FLAG --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,Engine,DBInstanceStatus,VpcId]' --output table

echo -e "\n🗄️ RDS CLUSTERS (Aurora):"
aws rds describe-db-clusters $REGION_FLAG --query 'DBClusters[*].[DBClusterIdentifier,Engine,Status,VpcId]' --output table

echo -e "\n⚡ DYNAMODB TABLES:"
aws dynamodb list-tables $REGION_FLAG --query 'TableNames' --output table

echo -e "\n🧠 ELASTICACHE CLUSTERS:"
aws elasticache describe-cache-clusters $REGION_FLAG --query 'CacheClusters[*].[CacheClusterId,CacheNodeType,Engine,CacheClusterStatus]' --output table

# STORAGE
echo -e "\n🪣 S3 BUCKETS:"
aws s3 ls $REGION_FLAG

echo -e "\n🗄️ EFS FILE SYSTEMS:"
aws efs describe-file-systems $REGION_FLAG --query 'FileSystems[*].[FileSystemId,CreationTime,LifeCycleState,NumberOfMountTargets]' --output table

# SERVERLESS & CONTAINERS
echo -e "\n⚡ LAMBDA FUNCTIONS:"
aws lambda list-functions $REGION_FLAG --query 'Functions[*].[FunctionName,Runtime,LastModified,CodeSize]' --output table

echo -e "\n🐳 ECS CLUSTERS:"
aws ecs list-clusters $REGION_FLAG --query 'clusterArns' --output table

echo -e "\n📦 ECR REPOSITORIES:"
aws ecr describe-repositories $REGION_FLAG --query 'repositories[*].[repositoryName,createdAt,repositoryUri]' --output table

# SECURITY & ACCESS
echo -e "\n👥 IAM USERS:"
aws iam list-users $REGION_FLAG --query 'Users[*].[UserName,CreateDate,PasswordLastUsed]' --output table

echo -e "\n🔑 IAM ROLES:"
aws iam list-roles $REGION_FLAG --query 'Roles[*].[RoleName,CreateDate,Description]' --output table

echo -e "\n🔐 SECURITY GROUPS:"
aws ec2 describe-security-groups $REGION_FLAG --query 'SecurityGroups[*].[GroupId,GroupName,VpcId,Description]' --output table

echo -e "\n🔑 KEY PAIRS:"
aws ec2 describe-key-pairs $REGION_FLAG --query 'KeyPairs[*].[KeyName,KeyFingerprint]' --output table

# MONITORING & LOGS
echo -e "\n📊 CLOUDWATCH ALARMS:"
aws cloudwatch describe-alarms $REGION_FLAG --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName]' --output table

echo -e "\n📝 CLOUDWATCH LOG GROUPS:"
aws logs describe-log-groups $REGION_FLAG --query 'logGroups[*].[logGroupName,creationTime,retentionInDays]' --output table

# DNS & CDN
echo -e "\n🌍 ROUTE 53 HOSTED ZONES:"
aws route53 list-hosted-zones $REGION_FLAG --query 'HostedZones[*].[Id,Name,ResourceRecordSetCount]' --output table

echo -e "\n🚀 CLOUDFRONT DISTRIBUTIONS:"
aws cloudfront list-distributions $REGION_FLAG --query 'DistributionList.Items[*].[Id,DomainName,Status,Enabled]' --output table

# API & MESSAGING
echo -e "\n🔌 API GATEWAYS:"
aws apigateway get-rest-apis $REGION_FLAG --query 'items[*].[id,name,createdDate]' --output table

echo -e "\n📮 SQS QUEUES:"
aws sqs list-queues $REGION_FLAG --query 'QueueUrls' --output table

echo -e "\n📢 SNS TOPICS:"
aws sns list-topics $REGION_FLAG --query 'Topics[*].TopicArn' --output table

# ANALYTICS & ML
echo -e "\n📊 REDSHIFT CLUSTERS:"
aws redshift describe-clusters $REGION_FLAG --query 'Clusters[*].[ClusterIdentifier,NodeType,ClusterStatus,VpcId]' --output table

echo -e "\n🧠 SAGEMAKER ENDPOINTS:"
aws sagemaker list-endpoints $REGION_FLAG --query 'Endpoints[*].[EndpointName,EndpointStatus,CreationTime]' --output table

echo -e "\n✅ AUDITORIA COMPLETADA"
echo "================================="