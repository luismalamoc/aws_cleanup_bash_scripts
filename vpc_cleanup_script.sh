#!/bin/bash

# Script para limpiar completamente una VPC y todos sus recursos
# Uso: ./cleanup_vpc.sh <vpc-id> [--region <region>] [--dry-run] [--force-default]
# 
# Opciones:
#   --region: Especifica la región AWS (ej: us-east-1)
#   --dry-run: Solo muestra qué se eliminaría sin ejecutar
#   --force-default: Permite limpiar VPC por defecto (pero no eliminarla)

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
VPC_ID=""
REGION=""
REGION_FLAG=""
DRY_RUN=false
FORCE_DEFAULT=false
ERRORS=()

# Función para logging
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ERRORS+=("$1")
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Función para mostrar ayuda
show_help() {
    cat << EOF
Script de Limpieza Completa de VPC

Uso: $0 <vpc-id> [opciones]

Opciones:
    --region <region>   Especifica la región AWS (ej: us-east-1, us-west-2)
    --dry-run          Solo muestra qué se eliminaría sin ejecutar
    --force-default    Permite limpiar VPC por defecto (pero no eliminarla)
    -h, --help         Muestra esta ayuda

Ejemplos:
    $0 vpc-12345678                              # Limpia VPC en región por defecto
    $0 vpc-12345678 --region us-east-1           # Limpia VPC en us-east-1
    $0 vpc-12345678 --region us-west-2 --dry-run # Solo muestra qué se haría
    $0 vpc-12345678 --force-default              # Limpia VPC por defecto

El script elimina recursos en el siguiente orden:
1. Instancias EC2
2. Load Balancers (ALB/NLB/CLB)
3. Bases de datos RDS
4. NAT Gateways
5. VPC Endpoints
6. Security Groups personalizados
7. Network ACLs personalizadas
8. Route Tables personalizadas
9. Subnets (solo en VPCs no-default)
10. Internet Gateway (solo en VPCs no-default)
11. VPC (solo si no es default)
EOF
}

# Función para ejecutar comando con opción dry-run
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $description"
        echo "  Comando: $cmd"
    else
        log "$description"
        if eval "$cmd" 2>/dev/null; then
            success "✓ $description"
        else
            error "✗ Falló: $description"
        fi
    fi
}

# Verificar si la VPC existe y obtener info - FUNCIÓN CORREGIDA
check_vpc() {
    log "Verificando VPC: $VPC_ID en región: ${REGION:-'por defecto'}"
    
    echo "DEBUG: Ejecutando comando de verificación VPC..."
    echo "DEBUG: aws ec2 describe-vpcs $REGION_FLAG --vpc-ids $VPC_ID --query 'Vpcs[0]'"
    
    # Verificar primero si la VPC existe
    local vpc_exists
    vpc_exists=$(aws ec2 describe-vpcs $REGION_FLAG --vpc-ids "$VPC_ID" --query 'length(Vpcs)' --output text 2>/dev/null)
    
    if [ "$vpc_exists" != "1" ]; then
        error "VPC $VPC_ID no encontrada en la región especificada"
        exit 1
    fi
    
    # Obtener información de la VPC
    local is_default
    is_default=$(aws ec2 describe-vpcs $REGION_FLAG --vpc-ids "$VPC_ID" --query 'Vpcs[0].IsDefault' --output text 2>/dev/null)
    
    # Convertir valores null/None a false
    if [ "$is_default" = "None" ] || [ "$is_default" = "null" ] || [ -z "$is_default" ]; then
        is_default="false"
    fi
    
    echo "DEBUG: is_default extraído: $is_default"
    
    if [ "$is_default" = "true" ] && [ "$FORCE_DEFAULT" = false ]; then
        error "Esta es una VPC por defecto. No se puede eliminar completamente."
        warn "Usa --force-default para limpiar solo los recursos personalizados."
        exit 1
    fi
    
    if [ "$is_default" = "true" ]; then
        warn "VPC por defecto detectada. Se limpiarán solo recursos personalizados."
    fi
    
    success "VPC $VPC_ID encontrada (Default: $is_default)"
    echo "$is_default"  # Esta línea devuelve el valor para uso posterior
}

# 1. Eliminar instancias EC2
cleanup_ec2_instances() {
    log "🔍 Buscando instancias EC2..."
    
    local instances
    instances=$(aws ec2 describe-instances $REGION_FLAG \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,stopped,stopping" \
        --query 'Reservations[*].Instances[*].InstanceId' --output text)
    
    if [ -n "$instances" ] && [ "$instances" != "" ]; then
        for instance in $instances; do
            execute_command "aws ec2 terminate-instance $REGION_FLAG --instance-ids $instance" \
                "Terminando instancia EC2: $instance"
        done
        
        if [ "$DRY_RUN" = false ]; then
            log "Esperando a que las instancias terminen..."
            aws ec2 wait instance-terminated $REGION_FLAG --instance-ids $instances 2>/dev/null || true
        fi
    else
        success "✓ No hay instancias EC2 que eliminar"
    fi
}

# 2. Eliminar Load Balancers
cleanup_load_balancers() {
    log "🔍 Buscando Load Balancers..."
    
    # ALB/NLB
    local albs
    albs=$(aws elbv2 describe-load-balancers $REGION_FLAG \
        --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text 2>/dev/null || true)
    
    if [ -n "$albs" ] && [ "$albs" != "" ]; then
        for alb in $albs; do
            execute_command "aws elbv2 delete-load-balancer $REGION_FLAG --load-balancer-arn $alb" \
                "Eliminando ALB/NLB: $alb"
        done
    fi
    
    # Classic Load Balancers
    local clbs
    clbs=$(aws elb describe-load-balancers $REGION_FLAG \
        --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].LoadBalancerName" --output text 2>/dev/null || true)
    
    if [ -n "$clbs" ] && [ "$clbs" != "" ]; then
        for clb in $clbs; do
            execute_command "aws elb delete-load-balancer $REGION_FLAG --load-balancer-name $clb" \
                "Eliminando CLB: $clb"
        done
    fi
    
    if [ -z "$albs" ] && [ -z "$clbs" ]; then
        success "✓ No hay Load Balancers que eliminar"
    fi
}

# 3. Eliminar bases de datos RDS
cleanup_rds() {
    log "🔍 Buscando instancias RDS..."
    
    local rds_instances
    rds_instances=$(aws rds describe-db-instances $REGION_FLAG \
        --query "DBInstances[?DBSubnetGroup.VpcId=='$VPC_ID'].DBInstanceIdentifier" --output text 2>/dev/null || true)
    
    if [ -n "$rds_instances" ] && [ "$rds_instances" != "" ]; then
        for db in $rds_instances; do
            execute_command "aws rds delete-db-instance $REGION_FLAG --db-instance-identifier $db --skip-final-snapshot" \
                "Eliminando instancia RDS: $db"
        done
    else
        success "✓ No hay instancias RDS que eliminar"
    fi
    
    # Clusters Aurora
    local clusters
    clusters=$(aws rds describe-db-clusters $REGION_FLAG \
        --query "DBClusters[?DBSubnetGroup=='$VPC_ID'].DBClusterIdentifier" --output text 2>/dev/null || true)
    
    if [ -n "$clusters" ] && [ "$clusters" != "" ]; then
        for cluster in $clusters; do
            execute_command "aws rds delete-db-cluster $REGION_FLAG --db-cluster-identifier $cluster --skip-final-snapshot" \
                "Eliminando cluster Aurora: $cluster"
        done
    fi
}

# 4. Eliminar NAT Gateways
cleanup_nat_gateways() {
    log "🔍 Buscando NAT Gateways..."
    
    local nat_gws
    nat_gws=$(aws ec2 describe-nat-gateways $REGION_FLAG \
        --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
        --query 'NatGateways[*].NatGatewayId' --output text)
    
    if [ -n "$nat_gws" ] && [ "$nat_gws" != "" ]; then
        for nat in $nat_gws; do
            execute_command "aws ec2 delete-nat-gateway $REGION_FLAG --nat-gateway-id $nat" \
                "Eliminando NAT Gateway: $nat"
        done
        
        if [ "$DRY_RUN" = false ]; then
            log "Esperando a que los NAT Gateways se eliminen..."
            for nat in $nat_gws; do
                aws ec2 wait nat-gateway-deleted $REGION_FLAG --nat-gateway-ids "$nat" 2>/dev/null || true
            done
        fi
    else
        success "✓ No hay NAT Gateways que eliminar"
    fi
}

# 5. Eliminar VPC Endpoints
cleanup_vpc_endpoints() {
    log "🔍 Buscando VPC Endpoints..."
    
    local endpoints
    endpoints=$(aws ec2 describe-vpc-endpoints $REGION_FLAG \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'VpcEndpoints[*].VpcEndpointId' --output text)
    
    if [ -n "$endpoints" ] && [ "$endpoints" != "" ]; then
        execute_command "aws ec2 delete-vpc-endpoints $REGION_FLAG --vpc-endpoint-ids $endpoints" \
            "Eliminando VPC Endpoints: $endpoints"
    else
        success "✓ No hay VPC Endpoints que eliminar"
    fi
}

# 6. Eliminar Security Groups
cleanup_security_groups() {
    log "🔍 Buscando Security Groups..."
    
    # Primero obtener todos los security groups no-default
    local security_groups
    security_groups=$(aws ec2 describe-security-groups $REGION_FLAG \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
    
    if [ -n "$security_groups" ] && [ "$security_groups" != "" ]; then
        # Eliminar referencias cruzadas primero
        for sg in $security_groups; do
            # Obtener reglas que referencian otros security groups
            local ingress_rules
            ingress_rules=$(aws ec2 describe-security-groups $REGION_FLAG --group-ids "$sg" \
                --query 'SecurityGroups[0].IpPermissions[?UserIdGroupPairs[0].GroupId]' --output json)
            
            if [ "$ingress_rules" != "[]" ] && [ "$ingress_rules" != "null" ]; then
                execute_command "aws ec2 revoke-security-group-ingress $REGION_FLAG --group-id $sg --ip-permissions '$ingress_rules'" \
                    "Eliminando reglas ingress de SG: $sg"
            fi
            
            local egress_rules
            egress_rules=$(aws ec2 describe-security-groups $REGION_FLAG --group-ids "$sg" \
                --query 'SecurityGroups[0].IpPermissions[?UserIdGroupPairs[0].GroupId]' --output json)
            
            if [ "$egress_rules" != "[]" ] && [ "$egress_rules" != "null" ]; then
                execute_command "aws ec2 revoke-security-group-egress $REGION_FLAG --group-id $sg --ip-permissions '$egress_rules'" \
                    "Eliminando reglas egress de SG: $sg"
            fi
        done
        
        # Ahora eliminar los security groups
        for sg in $security_groups; do
            execute_command "aws ec2 delete-security-group $REGION_FLAG --group-id $sg" \
                "Eliminando Security Group: $sg"
        done
    else
        success "✓ No hay Security Groups personalizados que eliminar"
    fi
}

# 7. Eliminar Network ACLs personalizadas
cleanup_network_acls() {
    log "🔍 Buscando Network ACLs personalizadas..."
    
    local nacls
    nacls=$(aws ec2 describe-network-acls $REGION_FLAG \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'NetworkAcls[?IsDefault==`false`].NetworkAclId' --output text)
    
    if [ -n "$nacls" ] && [ "$nacls" != "" ]; then
        for nacl in $nacls; do
            execute_command "aws ec2 delete-network-acl $REGION_FLAG --network-acl-id $nacl" \
                "Eliminando Network ACL: $nacl"
        done
    else
        success "✓ No hay Network ACLs personalizadas que eliminar"
    fi
}

# 8. Eliminar Route Tables personalizadas
cleanup_route_tables() {
    log "🔍 Buscando Route Tables personalizadas..."
    
    local route_tables
    route_tables=$(aws ec2 describe-route-tables $REGION_FLAG \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
    
    if [ -n "$route_tables" ] && [ "$route_tables" != "" ]; then
        for rt in $route_tables; do
            # Primero desasociar subnets
            local associations
            associations=$(aws ec2 describe-route-tables $REGION_FLAG --route-table-ids "$rt" \
                --query 'RouteTables[0].Associations[?Main!=`true`].RouteTableAssociationId' --output text)
            
            if [ -n "$associations" ] && [ "$associations" != "" ]; then
                for assoc in $associations; do
                    execute_command "aws ec2 disassociate-route-table $REGION_FLAG --association-id $assoc" \
                        "Desasociando Route Table: $rt"
                done
            fi
            
            execute_command "aws ec2 delete-route-table $REGION_FLAG --route-table-id $rt" \
                "Eliminando Route Table: $rt"
        done
    else
        success "✓ No hay Route Tables personalizadas que eliminar"
    fi
}

# 9. Eliminar Subnets (solo si no es VPC default)
cleanup_subnets() {
    local is_default="$1"
    
    if [ "$is_default" = "true" ]; then
        warn "⚠️  Saltando eliminación de subnets (VPC por defecto)"
        return
    fi
    
    log "🔍 Buscando Subnets..."
    
    local subnets
    subnets=$(aws ec2 describe-subnets $REGION_FLAG \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[*].SubnetId' --output text)
    
    if [ -n "$subnets" ] && [ "$subnets" != "" ]; then
        for subnet in $subnets; do
            execute_command "aws ec2 delete-subnet $REGION_FLAG --subnet-id $subnet" \
                "Eliminando Subnet: $subnet"
        done
    else
        success "✓ No hay Subnets que eliminar"
    fi
}

# 10. Eliminar Internet Gateway (solo si no es VPC default)
cleanup_internet_gateway() {
    local is_default="$1"
    
    if [ "$is_default" = "true" ]; then
        warn "⚠️  Saltando eliminación de Internet Gateway (VPC por defecto)"
        return
    fi
    
    log "🔍 Buscando Internet Gateway..."
    
    local igw
    igw=$(aws ec2 describe-internet-gateways $REGION_FLAG \
        --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
        --query 'InternetGateways[*].InternetGatewayId' --output text)
    
    if [ -n "$igw" ] && [ "$igw" != "" ]; then
        execute_command "aws ec2 detach-internet-gateway $REGION_FLAG --internet-gateway-id $igw --vpc-id $VPC_ID" \
            "Desasociando Internet Gateway: $igw"
        execute_command "aws ec2 delete-internet-gateway $REGION_FLAG --internet-gateway-id $igw" \
            "Eliminando Internet Gateway: $igw"
    else
        success "✓ No hay Internet Gateway que eliminar"
    fi
}

# 11. Eliminar VPC (solo si no es default)
cleanup_vpc() {
    local is_default="$1"
    
    if [ "$is_default" = "true" ]; then
        warn "⚠️  No se puede eliminar VPC por defecto"
        return
    fi
    
    execute_command "aws ec2 delete-vpc $REGION_FLAG --vpc-id $VPC_ID" \
        "Eliminando VPC: $VPC_ID"
}

# Limpiar Elastic IPs huérfanas
cleanup_elastic_ips() {
    log "🔍 Buscando Elastic IPs sin asociar..."
    
    local eips
    eips=$(aws ec2 describe-addresses $REGION_FLAG \
        --query 'Addresses[?AssociationId==null].AllocationId' --output text)
    
    if [ -n "$eips" ] && [ "$eips" != "" ]; then
        for eip in $eips; do
            execute_command "aws ec2 release-address $REGION_FLAG --allocation-id $eip" \
                "Liberando Elastic IP: $eip"
        done
    else
        success "✓ No hay Elastic IPs sin asociar"
    fi
}

# Limpiar Network Interfaces huérfanas
cleanup_network_interfaces() {
    log "🔍 Buscando Network Interfaces huérfanas..."
    
    local enis
    enis=$(aws ec2 describe-network-interfaces $REGION_FLAG \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=available" \
        --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text)
    
    if [ -n "$enis" ] && [ "$enis" != "" ]; then
        for eni in $enis; do
            execute_command "aws ec2 delete-network-interface $REGION_FLAG --network-interface-id $eni" \
                "Eliminando Network Interface: $eni"
        done
    else
        success "✓ No hay Network Interfaces huérfanas"
    fi
}

# Función principal
main() {
    # Verificar dependencias
    command -v aws >/dev/null 2>&1 || { error "AWS CLI no está instalado"; exit 1; }
    
    # Debug: mostrar argumentos recibidos
    echo "DEBUG: Argumentos recibidos: $@"
    echo "DEBUG: Número de argumentos: $#"
    
    # Parsear argumentos
    while [[ $# -gt 0 ]]; do
        echo "DEBUG: Procesando argumento: $1"
        case $1 in
            --region)
                if [[ $# -lt 2 ]]; then
                    error "La opción --region requiere un valor"
                    exit 1
                fi
                REGION="$2"
                REGION_FLAG="--region $REGION"
                echo "DEBUG: Región establecida: $REGION"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                echo "DEBUG: Dry-run activado"
                shift
                ;;
            --force-default)
                FORCE_DEFAULT=true
                echo "DEBUG: Force-default activado"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            vpc-*)
                VPC_ID="$1"
                echo "DEBUG: VPC ID establecido: $VPC_ID"
                shift
                ;;
            *)
                error "Opción desconocida: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Validar VPC ID
    if [ -z "$VPC_ID" ]; then
        error "Debes especificar un VPC ID"
        echo ""
        echo "Uso: $0 vpc-12345678 [--region us-east-1] [--dry-run] [--force-default]"
        echo ""
        show_help
        exit 1
    fi
    
    echo "DEBUG: Iniciando verificación de VPC..."
    
    # Verificar VPC
    local is_default
    is_default=$(check_vpc)
    
    echo "DEBUG: VPC verificada, is_default: $is_default"
    
    echo ""
    log "🚀 Iniciando limpieza de VPC: $VPC_ID"
    if [ -n "$REGION" ]; then
        log "🌍 Región: $REGION"
    else
        log "🌍 Usando región por defecto del perfil AWS"
    fi
    if [ "$DRY_RUN" = true ]; then
        warn "MODO DRY-RUN: No se ejecutarán cambios reales"
    fi
    echo ""
    
    # Ejecutar limpieza en orden
    cleanup_ec2_instances
    cleanup_load_balancers
    cleanup_rds
    cleanup_nat_gateways
    cleanup_vpc_endpoints
    cleanup_network_interfaces
    cleanup_elastic_ips
    cleanup_security_groups
    cleanup_network_acls
    cleanup_route_tables
    cleanup_subnets "$is_default"
    cleanup_internet_gateway "$is_default"
    cleanup_vpc "$is_default"
    
    # Resumen final
    echo ""
    echo "========================================"
    if [ ${#ERRORS[@]} -eq 0 ]; then
        success "🎉 LIMPIEZA COMPLETADA EXITOSAMENTE"
    else
        warn "⚠️  LIMPIEZA COMPLETADA CON ERRORES:"
        for error in "${ERRORS[@]}"; do
            echo -e "  ${RED}✗${NC} $error"
        done
    fi
    echo "========================================"
}

# Ejecutar script principal
main "$@"