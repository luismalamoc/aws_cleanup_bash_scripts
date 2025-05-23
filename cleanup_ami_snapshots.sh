#!/bin/bash

# Script para limpiar AMIs personalizadas y snapshots asociados
# Uso: ./cleanup_ami_snapshots.sh [--region <region>] [--dry-run] [--filter <pattern>] [--owner-id <owner-id>]
# 
# Opciones:
#   --region: Especifica la región AWS (ej: us-east-1)
#   --dry-run: Solo muestra qué se eliminaría sin ejecutar
#   --filter: Filtro para nombres de AMI (ej: "rundeck", "ami-rundeck*")
#   --owner-id: ID del propietario (por defecto usa tu account ID)

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
REGION=""
REGION_FLAG=""
DRY_RUN=false
FILTER_PATTERN=""
OWNER_ID=""
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
Script de Limpieza de AMIs y Snapshots

Uso: $0 [opciones]

Opciones:
    --region <region>       Especifica la región AWS (ej: us-east-1, us-west-2)
    --dry-run              Solo muestra qué se eliminaría sin ejecutar
    --filter <pattern>     Filtro para nombres de AMI (ej: "rundeck", "ami-rundeck*")
    --owner-id <id>        ID del propietario (por defecto usa tu account ID)
    -h, --help             Muestra esta ayuda

Ejemplos:
    $0 --region us-east-2                           # Limpia todas las AMIs propias en us-east-2
    $0 --region us-east-2 --filter "rundeck"        # Solo AMIs que contengan "rundeck"
    $0 --region us-east-2 --dry-run                 # Solo muestra qué se haría
    $0 --region us-east-2 --filter "*2022*"         # Solo AMIs del 2022

IMPORTANTE:
- El script solo elimina AMIs que te pertenecen (owner-id)
- Primero desregistra las AMIs, luego elimina los snapshots asociados
- Los snapshots compartidos con otras AMIs NO se eliminan por seguridad
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

# Obtener el account ID actual
get_account_id() {
    if [ -z "$OWNER_ID" ]; then
        OWNER_ID=$(aws sts get-caller-identity $REGION_FLAG --query 'Account' --output text 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$OWNER_ID" ]; then
            error "No se pudo obtener el Account ID. Verifica tus credenciales AWS."
            exit 1
        fi
    fi
    log "Account ID: $OWNER_ID"
}

# Listar AMIs con filtros - solo mostrar tabla
show_amis_table() {
    log "🔍 Buscando AMIs personalizadas..."
    
    local filter_query='Images[*].[ImageId,Name,State,CreationDate]'
    local base_filters="Name=owner-id,Values=$OWNER_ID"
    
    # Agregar filtro de nombre si se especifica
    if [ -n "$FILTER_PATTERN" ]; then
        base_filters="$base_filters Name=name,Values=*${FILTER_PATTERN}*"
    fi
    
    echo "DEBUG: Ejecutando: aws ec2 describe-images $REGION_FLAG --owners $OWNER_ID --filters $base_filters --query '$filter_query' --output table"
    
    aws ec2 describe-images $REGION_FLAG \
        --owners "$OWNER_ID" \
        --filters "$base_filters" \
        --query "$filter_query" \
        --output table 2>/dev/null
}

# Obtener lista de AMI IDs
get_ami_ids() {
    local base_filters="Name=owner-id,Values=$OWNER_ID"
    
    # Agregar filtro de nombre si se especifica
    if [ -n "$FILTER_PATTERN" ]; then
        base_filters="$base_filters Name=name,Values=*${FILTER_PATTERN}*"
    fi
    
    aws ec2 describe-images $REGION_FLAG \
        --owners "$OWNER_ID" \
        --filters "$base_filters" \
        --query 'Images[*].ImageId' \
        --output text 2>/dev/null
}

# Obtener snapshots asociados a una AMI
get_ami_snapshots() {
    local ami_id="$1"
    
    aws ec2 describe-images $REGION_FLAG \
        --image-ids "$ami_id" \
        --query 'Images[0].BlockDeviceMappings[*].Ebs.SnapshotId' \
        --output text 2>/dev/null | tr '\t' ' '
}

# Verificar si un snapshot está siendo usado por otras AMIs
is_snapshot_in_use() {
    local snapshot_id="$1"
    
    local usage_count
    usage_count=$(aws ec2 describe-images $REGION_FLAG \
        --owners "$OWNER_ID" \
        --filters "Name=block-device-mapping.snapshot-id,Values=$snapshot_id" \
        --query 'length(Images)' \
        --output text 2>/dev/null)
    
    [ "$usage_count" -gt 1 ]
}

# Limpiar AMIs y snapshots
cleanup_amis() {
    local ami_ids="$1"
    
    if [ -z "$ami_ids" ] || [ "$ami_ids" = "" ]; then
        success "✓ No hay AMIs que eliminar"
        return
    fi
    
    log "🗑️  Iniciando eliminación de AMIs..."
    
    # Array para almacenar snapshots a eliminar
    local snapshots_to_delete=()
    
    # Convertir string de AMI IDs en array
    local ami_array=($ami_ids)
    local total_amis=${#ami_array[@]}
    local current=0
    
    log "Total de AMIs a procesar: $total_amis"
    
    # Procesar cada AMI
    for ami_id in "${ami_array[@]}"; do
        current=$((current + 1))
        log "[$current/$total_amis] Procesando AMI: $ami_id"
        
        # Obtener información de la AMI
        local ami_name
        ami_name=$(aws ec2 describe-images $REGION_FLAG \
            --image-ids "$ami_id" \
            --query 'Images[0].Name' \
            --output text 2>/dev/null)
        
        if [ -n "$ami_name" ] && [ "$ami_name" != "None" ]; then
            log "  Nombre: $ami_name"
        fi
        
        # Obtener snapshots asociados ANTES de desregistrar la AMI
        local ami_snapshots
        ami_snapshots=$(get_ami_snapshots "$ami_id")
        
        if [ -n "$ami_snapshots" ] && [ "$ami_snapshots" != "" ]; then
            log "  Snapshots asociados: $ami_snapshots"
            
            # Verificar cada snapshot para ver si se puede eliminar
            for snap_id in $ami_snapshots; do
                if [ -n "$snap_id" ] && [ "$snap_id" != "None" ]; then
                    if ! is_snapshot_in_use "$snap_id"; then
                        snapshots_to_delete+=("$snap_id")
                        log "  ✓ Snapshot $snap_id marcado para eliminación"
                    else
                        warn "  ⚠️  Snapshot $snap_id está siendo usado por otras AMIs, se preservará"
                    fi
                fi
            done
        else
            log "  No tiene snapshots asociados"
        fi
        
        # Desregistrar AMI
        execute_command "aws ec2 deregister-image $REGION_FLAG --image-id $ami_id" \
            "Desregistrando AMI: $ami_id"
        
        # Pequeña pausa para evitar throttling
        sleep 0.5
    done
    
    # Eliminar snapshots
    if [ ${#snapshots_to_delete[@]} -gt 0 ]; then
        log "🗑️  Eliminando ${#snapshots_to_delete[@]} snapshots..."
        
        local snap_current=0
        for snap_id in "${snapshots_to_delete[@]}"; do
            snap_current=$((snap_current + 1))
            execute_command "aws ec2 delete-snapshot $REGION_FLAG --snapshot-id $snap_id" \
                "[$snap_current/${#snapshots_to_delete[@]}] Eliminando snapshot: $snap_id"
            
            # Pequeña pausa para evitar throttling
            sleep 0.2
        done
    else
        log "No hay snapshots seguros para eliminar"
    fi
}

# Mostrar resumen de recursos
show_summary() {
    echo ""
    echo "========================================"
    echo "📊 RESUMEN DE RECURSOS ENCONTRADOS"
    echo "========================================"
    
    # Mostrar tabla de AMIs
    show_amis_table
    
    # Contar AMIs
    local ami_ids
    ami_ids=$(get_ami_ids)
    
    if [ -n "$ami_ids" ] && [ "$ami_ids" != "" ]; then
        local ami_array=($ami_ids)
        local ami_count=${#ami_array[@]}
        
        log "🖥️  Total AMIs encontradas: $ami_count"
        
        # Contar snapshots asociados
        local total_snapshots=0
        for ami_id in "${ami_array[@]}"; do
            local snap_count
            snap_count=$(get_ami_snapshots "$ami_id" | wc -w)
            total_snapshots=$((total_snapshots + snap_count))
        done
        
        log "📷 Snapshots asociados: $total_snapshots"
    else
        success "✓ No se encontraron recursos para limpiar"
    fi
    
    echo "========================================"
}

# Función principal
main() {
    # Verificar dependencias
    command -v aws >/dev/null 2>&1 || { error "AWS CLI no está instalado"; exit 1; }
    
    # Parsear argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                if [[ $# -lt 2 ]]; then
                    error "La opción --region requiere un valor"
                    exit 1
                fi
                REGION="$2"
                REGION_FLAG="--region $REGION"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --filter)
                if [[ $# -lt 2 ]]; then
                    error "La opción --filter requiere un valor"
                    exit 1
                fi
                FILTER_PATTERN="$2"
                shift 2
                ;;
            --owner-id)
                if [[ $# -lt 2 ]]; then
                    error "La opción --owner-id requiere un valor"
                    exit 1
                fi
                OWNER_ID="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Opción desconocida: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo ""
    log "🚀 INICIANDO LIMPIEZA DE AMIs Y SNAPSHOTS"
    if [ -n "$REGION" ]; then
        log "🌍 Región: $REGION"
    else
        log "🌍 Usando región por defecto del perfil AWS"
    fi
    if [ -n "$FILTER_PATTERN" ]; then
        log "🔍 Filtro: *$FILTER_PATTERN*"
    fi
    if [ "$DRY_RUN" = true ]; then
        warn "MODO DRY-RUN: No se ejecutarán cambios reales"
    fi
    echo ""
    
    # Obtener Account ID
    get_account_id
    
    # Mostrar resumen
    show_summary
    
    # Confirmar antes de proceder (solo si no es dry-run)
    if [ "$DRY_RUN" = false ]; then
        echo ""
        read -p "¿Deseas proceder con la eliminación? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Operación cancelada por el usuario"
            exit 0
        fi
    fi
    
    # Obtener AMIs para limpiar
    local ami_ids
    ami_ids=$(get_ami_ids)
    
    # Ejecutar limpieza
    cleanup_amis "$ami_ids"
    
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