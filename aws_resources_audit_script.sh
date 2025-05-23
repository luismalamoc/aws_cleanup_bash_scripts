#!/bin/bash

# Script para auditar todos los recursos principales en AWS
# Incluyendo todos los servicios que aparecen en facturación
# Uso: ./aws_audit_complete.sh [region]
# Ejemplo: ./aws_audit_complete.sh us-east-1

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
echo "Fecha: $(date)"
echo ""

# NETWORKING & VPC (Servicio con mayor costo)
echo -e "\n🌐 VPCs:"
aws ec2 describe-vpcs $REGION_FLAG --query 'Vpcs[*].[VpcId,State,CidrBlock,IsDefault,Tags[?Key==`Name`].Value|[0]]' --output table

echo -e "\n🔗 ELASTIC IPs:"
aws ec2 describe-addresses $REGION_FLAG --query 'Addresses[*].[PublicIp,AllocationId,AssociationId,InstanceId,Domain]' --output table

echo -e "\n🌍 NAT GATEWAYS:"
aws ec2 describe-nat-gateways $REGION_FLAG --query 'NatGateways[*].[NatGatewayId,State,VpcId,SubnetId,Tags[?Key==`Name`].Value|[0]]' --output table

echo -e "\n🌐 INTERNET GATEWAYS:"
aws ec2 describe-internet-gateways $REGION_FLAG --query 'InternetGateways[*].[InternetGatewayId,Attachments[0].VpcId,Attachments[0].State,Tags[?Key==`Name`].Value|[0]]' --output table

echo -e "\n📡 SUBNETS:"
aws ec2 describe-subnets $REGION_FLAG --query 'Subnets[*].[SubnetId,VpcId,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch,Tags[?Key==`Name`].Value|[0]]' --output table

echo -e "\n🛣️ ROUTE TABLES:"
aws ec2 describe-route-tables $REGION_FLAG --query 'RouteTables[*].[RouteTableId,VpcId,Associations[0].Main,Tags[?Key==`Name`].Value|[0]]' --output table

# CONTAINERS & ORCHESTRATION
echo -e "\n🐳 ECS CLUSTERS:"
aws ecs list-clusters $REGION_FLAG --query 'clusterArns' --output table

if [ "$(aws ecs list-clusters $REGION_FLAG --query 'length(clusterArns)')" -gt 0 ]; then
    echo -e "\n🐳 ECS SERVICES DETALLE:"
    for cluster in $(aws ecs list-clusters $REGION_FLAG --query 'clusterArns[]' --output text); do
        cluster_name=$(basename $cluster)
        echo "Cluster: $cluster_name"
        aws ecs list-services $REGION_FLAG --cluster $cluster_name --query 'serviceArns' --output table
    done
fi

echo -e "\n📦 ECR REPOSITORIES:"
aws ecr describe-repositories $REGION_FLAG --query 'repositories[*].[repositoryName,createdAt,repositoryUri,imageScanningConfiguration.scanOnPush]' --output table

echo -e "\n☸️ EKS CLUSTERS:"
aws eks list-clusters $REGION_FLAG --query 'clusters' --output table

if [ "$(aws eks list-clusters $REGION_FLAG --query 'length(clusters)')" -gt 0 ]; then
    echo -e "\n☸️ EKS CLUSTERS DETALLE:"
    for cluster in $(aws eks list-clusters $REGION_FLAG --query 'clusters[]' --output text); do
        echo "Cluster EKS: $cluster"
        aws eks describe-cluster $REGION_FLAG --name $cluster --query 'cluster.[name,status,version,platformVersion]' --output table
    done
fi

# COMPUTE RESOURCES
echo -e "\n💻 INSTANCIAS EC2:"
aws ec2 describe-instances $REGION_FLAG --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,PublicIpAddress,VpcId,Tags[?Key==`Name`].Value|[0]]' --output table

echo -e "\n🖥️ IMAGENES AMI PERSONALIZADAS:"
aws ec2 describe-images $REGION_FLAG --owners self --query 'Images[*].[ImageId,Name,State,CreationDate,Architecture]' --output table

echo -e "\n📦 VOLUMENES EBS:"
aws ec2 describe-volumes $REGION_FLAG --query 'Volumes[*].[VolumeId,Size,VolumeType,State,Attachments[0].InstanceId,Tags[?Key==`Name`].Value|[0]]' --output table

echo -e "\n📷 SNAPSHOTS EBS:"
aws ec2 describe-snapshots $REGION_FLAG --owner-ids self --query 'Snapshots[*].[SnapshotId,VolumeSize,State,StartTime,Description]' --output table

echo -e "\n💡 LIGHTSAIL INSTANCES:"
aws lightsail get-instances $REGION_FLAG --query 'instances[*].[name,blueprintName,bundleId,state.name,publicIpAddress]' --output table

# LOAD BALANCING
echo -e "\n⚖️ LOAD BALANCERS (ALB/NLB):"
aws elbv2 describe-load-balancers $REGION_FLAG --query 'LoadBalancers[*].[LoadBalancerName,Type,State.Code,VpcId,Scheme]' --output table

echo -e "\n⚖️ LOAD BALANCERS CLASICOS (ELB):"
aws elb describe-load-balancers $REGION_FLAG --query 'LoadBalancerDescriptions[*].[LoadBalancerName,Scheme,VPCId,Instances[0].InstanceId]' --output table

# DATABASES
echo -e "\n🗄️ RDS DATABASES:"
aws rds describe-db-instances $REGION_FLAG --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,Engine,DBInstanceStatus,VpcId,MultiAZ]' --output table

echo -e "\n🗄️ RDS CLUSTERS (Aurora):"
aws rds describe-db-clusters $REGION_FLAG --query 'DBClusters[*].[DBClusterIdentifier,Engine,Status,VpcId,DatabaseName]' --output table

echo -e "\n⚡ DYNAMODB TABLES:"
aws dynamodb list-tables $REGION_FLAG --query 'TableNames' --output table

if [ "$(aws dynamodb list-tables $REGION_FLAG --query 'length(TableNames)')" -gt 0 ]; then
    echo -e "\n⚡ DYNAMODB TABLES DETALLE:"
    for table in $(aws dynamodb list-tables $REGION_FLAG --query 'TableNames[]' --output text); do
        aws dynamodb describe-table $REGION_FLAG --table-name $table --query 'Table.[TableName,TableStatus,ItemCount,TableSizeBytes,BillingModeSummary.BillingMode]' --output table
    done
fi

echo -e "\n🧠 ELASTICACHE CLUSTERS:"
aws elasticache describe-cache-clusters $REGION_FLAG --query 'CacheClusters[*].[CacheClusterId,CacheNodeType,Engine,CacheClusterStatus,NumCacheNodes]' --output table

echo -e "\n🧠 ELASTICACHE REPLICATION GROUPS:"
aws elasticache describe-replication-groups $REGION_FLAG --query 'ReplicationGroups[*].[ReplicationGroupId,Status,NodeType,NumCacheClusters,Engine]' --output table

# STORAGE
echo -e "\n🪣 S3 BUCKETS:"
aws s3 ls $REGION_FLAG

echo -e "\n🪣 S3 BUCKETS DETALLE:"
for bucket in $(aws s3 ls --query 'Buckets[].Name' --output text); do
    echo "Bucket: $bucket"
    aws s3api get-bucket-location --bucket $bucket --output table 2>/dev/null || echo "  - No se puede acceder a la ubicación"
    aws s3 ls s3://$bucket --summarize --human-readable 2>/dev/null | tail -2 || echo "  - No se puede acceder al contenido"
done

echo -e "\n🗄️ EFS FILE SYSTEMS:"
aws efs describe-file-systems $REGION_FLAG --query 'FileSystems[*].[FileSystemId,CreationTime,LifeCycleState,NumberOfMountTargets,Name]' --output table

echo -e "\n🧊 GLACIER VAULTS:"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
if [ ! -z "$ACCOUNT_ID" ]; then
    aws glacier list-vaults $REGION_FLAG --account-id $ACCOUNT_ID --query 'VaultList[*].[VaultName,CreationDate,SizeInBytes,NumberOfArchives]' --output table
else
    echo "No se pudo obtener el Account ID para consultar Glacier"
fi

# SERVERLESS & FUNCTIONS
echo -e "\n⚡ LAMBDA FUNCTIONS:"
aws lambda list-functions $REGION_FLAG --query 'Functions[*].[FunctionName,Runtime,LastModified,CodeSize,Timeout]' --output table

echo -e "\n🔄 STEP FUNCTIONS:"
aws stepfunctions list-state-machines $REGION_FLAG --query 'stateMachines[*].[name,status,type,creationDate]' --output table

# SECURITY & ACCESS
echo -e "\n👥 IAM USERS:"
aws iam list-users --query 'Users[*].[UserName,CreateDate,PasswordLastUsed]' --output table

echo -e "\n🔑 IAM ROLES:"
aws iam list-roles --query 'Roles[*].[RoleName,CreateDate,Description]' --output table | head -20

echo -e "\n🔐 SECURITY GROUPS:"
aws ec2 describe-security-groups $REGION_FLAG --query 'SecurityGroups[*].[GroupId,GroupName,VpcId,Description]' --output table

echo -e "\n🔑 KEY PAIRS:"
aws ec2 describe-key-pairs $REGION_FLAG --query 'KeyPairs[*].[KeyName,KeyFingerprint,KeyType]' --output table

echo -e "\n🔐 SECRETS MANAGER:"
aws secretsmanager list-secrets $REGION_FLAG --query 'SecretList[*].[Name,Description,LastChangedDate,LastAccessedDate]' --output table

echo -e "\n🔑 KMS KEYS:"
aws kms list-keys $REGION_FLAG --query 'Keys[*].[KeyId]' --output table

echo -e "\n🛡️ WAF WEB ACLs:"
aws wafv2 list-web-acls $REGION_FLAG --scope REGIONAL --query 'WebACLs[*].[Name,Id,Description]' --output table

echo -e "\n🛡️ WAF CLOUDFRONT WEB ACLs:"
aws wafv2 list-web-acls --region us-east-1 --scope CLOUDFRONT --query 'WebACLs[*].[Name,Id,Description]' --output table

# MONITORING & LOGS
echo -e "\n📊 CLOUDWATCH ALARMS:"
aws cloudwatch describe-alarms $REGION_FLAG --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName,Namespace]' --output table

echo -e "\n📝 CLOUDWATCH LOG GROUPS:"
aws logs describe-log-groups $REGION_FLAG --query 'logGroups[*].[logGroupName,creationTime,retentionInDays,storedBytes]' --output table

# DNS & CDN
echo -e "\n🌍 ROUTE 53 HOSTED ZONES:"
aws route53 list-hosted-zones --query 'HostedZones[*].[Id,Name,ResourceRecordSetCount,Config.PrivateZone]' --output table

echo -e "\n🌍 ROUTE 53 DOMAINS (REGISTRAR):"
aws route53domains list-domains --query 'Domains[*].[DomainName,Expiry,AutoRenew,TransferLock]' --output table

echo -e "\n🚀 CLOUDFRONT DISTRIBUTIONS:"
aws cloudfront list-distributions --query 'DistributionList.Items[*].[Id,DomainName,Status,Enabled,Comment]' --output table

# API & MESSAGING
echo -e "\n🔌 API GATEWAYS (REST):"
aws apigateway get-rest-apis $REGION_FLAG --query 'items[*].[id,name,createdDate,endpointConfiguration.types[0]]' --output table

echo -e "\n🔌 API GATEWAYS V2 (HTTP/WebSocket):"
aws apigatewayv2 get-apis $REGION_FLAG --query 'Items[*].[ApiId,Name,ProtocolType,CreatedDate,ApiEndpoint]' --output table

echo -e "\n📮 SQS QUEUES:"
aws sqs list-queues $REGION_FLAG --query 'QueueUrls' --output table

if [ "$(aws sqs list-queues $REGION_FLAG --query 'length(QueueUrls)')" -gt 0 ]; then
    echo -e "\n📮 SQS QUEUES DETALLE:"
    for queue in $(aws sqs list-queues $REGION_FLAG --query 'QueueUrls[]' --output text); do
        queue_name=$(basename $queue)
        aws sqs get-queue-attributes $REGION_FLAG --queue-url $queue --attribute-names All --query 'Attributes.[ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible,QueueArn]' --output table
    done
fi

echo -e "\n📢 SNS TOPICS:"
aws sns list-topics $REGION_FLAG --query 'Topics[*].TopicArn' --output table

echo -e "\n📧 SES IDENTITIES:"
aws ses list-identities $REGION_FLAG --query 'Identities' --output table

# ANALYTICS & ML
echo -e "\n📊 REDSHIFT CLUSTERS:"
aws redshift describe-clusters $REGION_FLAG --query 'Clusters[*].[ClusterIdentifier,NodeType,ClusterStatus,VpcId,NumberOfNodes]' --output table

echo -e "\n🧠 SAGEMAKER ENDPOINTS:"
aws sagemaker list-endpoints $REGION_FLAG --query 'Endpoints[*].[EndpointName,EndpointStatus,CreationTime,LastModifiedTime]' --output table

echo -e "\n🔄 GLUE JOBS:"
aws glue get-jobs $REGION_FLAG --query 'Jobs[*].[Name,Role,CreatedOn,LastModifiedOn]' --output table

echo -e "\n🔄 GLUE CRAWLERS:"
aws glue get-crawlers $REGION_FLAG --query 'Crawlers[*].[Name,State,CreationTime,LastUpdated]' --output table

# INFRASTRUCTURE AS CODE
echo -e "\n📋 CLOUDFORMATION STACKS:"
aws cloudformation list-stacks $REGION_FLAG --query 'StackSummaries[?StackStatus!=`DELETE_COMPLETE`].[StackName,StackStatus,CreationTime,LastUpdatedTime]' --output table

echo -e "\n📦 SERVICE CATALOG PORTFOLIOS:"
aws servicecatalog list-portfolios $REGION_FLAG --query 'PortfolioDetails[*].[Id,DisplayName,Description,CreatedTime]' --output table

# DEVELOPMENT TOOLS
echo -e "\n💻 CLOUDSHELL ENVIRONMENTS:"
aws cloudshell describe-environments $REGION_FLAG --query 'environments[*].[environmentId,status,creationTime]' --output table 2>/dev/null || echo "CloudShell no disponible en esta región"

# RESUMEN DE COSTOS (si está disponible)
echo -e "\n💰 RESUMEN DE SERVICIOS ACTIVOS:"
echo "=================================="
echo "✅ EC2 Instances: $(aws ec2 describe-instances $REGION_FLAG --query 'length(Reservations[*].Instances[?State.Name==`running`][])')"
echo "✅ RDS Instances: $(aws rds describe-db-instances $REGION_FLAG --query 'length(DBInstances[?DBInstanceStatus==`available`])')"
echo "✅ Lambda Functions: $(aws lambda list-functions $REGION_FLAG --query 'length(Functions)')"
echo "✅ S3 Buckets: $(aws s3 ls --query 'length(Buckets)')"
echo "✅ ECS Clusters: $(aws ecs list-clusters $REGION_FLAG --query 'length(clusterArns)')"
echo "✅ Load Balancers: $(aws elbv2 describe-load-balancers $REGION_FLAG --query 'length(LoadBalancers)')"
echo "✅ NAT Gateways: $(aws ec2 describe-nat-gateways $REGION_FLAG --query 'length(NatGateways[?State==`available`])')"
echo "✅ ElastiCache Clusters: $(aws elasticache describe-cache-clusters $REGION_FLAG --query 'length(CacheClusters)')"

echo -e "\n✅ AUDITORIA COMPLETADA"
echo "================================="
echo "Fecha de finalización: $(date)"