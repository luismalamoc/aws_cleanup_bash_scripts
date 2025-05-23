#!/bin/bash

# Script para eliminar distribuciones CloudFront automáticamente
# Uso: ./cleanup_cloudfront.sh [--region <region>] [--dry-run] [--filter <pattern>] [--status <status>]
# 
# Opciones:
#   --region: Especifica la región AWS (ej: us-east-1) - NOTA: CloudFront es global pero afecta las credenciales
#   --dry-run: Solo muestra qué se eliminaría sin ejecutar
#   --filter: Filtro para nombres/comentarios de distribución (ej: "test", "dev")
#   --status: Solo distribuciones con estado específico (Deployed, InProgress, etc.)

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
STATUS_FILTER=""
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
Script de Limpieza Automática de CloudFront

Uso: $0 [opciones]

Opciones:
    --region <region>       Especifica la región AWS para credenciales
    --dry-run              Solo muestra qué se eliminaría sin ejecutar
    --filter <pattern>     Filtro para comentarios/nombres de distribución
    --status <status>      Solo distribuciones con estado específico (Deployed, InProgress)
    -h, --help             Muestra esta ayuda

Ejemplos:
    $0 --region us-east-1                        # Elimina todas las distribuciones
    $0 --region us-east-1 --dry-run              # Solo muestra qué se haría
    $0 --region us-east-1 --filter "test"        # Solo distribuciones con "test" en comentario
    $0 --region us-east-1 --status "Deployed"    # Solo distribuciones en estado "Deployed"

IMPORTANTE:
- CloudFront es un servicio global, --region solo afecta las credenciales AWS
- Solo se pueden eliminar distribuciones en estado "Deployed"
- Las distribuciones deben estar deshabilitadas antes de eliminar
- El script primero deshabilita las distribuciones si están habilitadas
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

# Listar distribuciones CloudFront
list_distributions() {
    log "🔍 Buscando distribuciones CloudFront..."
    
    # Obtener todas las distribuciones con mejor manejo de errores
    local aws_output
    aws_output=$(aws cloudfront list-distributions $REGION_FLAG --output json 2>&1)
    local aws_exit_code=$?
    
    if [ $aws_exit_code -ne 0 ]; then
        error "Error al listar distribuciones CloudFront:"
        error "$aws_output"
        echo "[]"
        return
    fi
    
    # Verificar si la respuesta es válida
    if [ -z "$aws_output" ] || [ "$aws_output" = "null" ]; then
        success "✓ No se encontraron distribuciones CloudFront (respuesta vacía)"
        echo "[]"
        return
    fi
    
    # Extraer Items de DistributionList
    local distributions_json
    distributions_json=$(echo "$aws_output" | jq -r '.DistributionList.Items // []' 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$distributions_json" ]; then
        error "Error procesando respuesta JSON de CloudFront"
        echo "[]"
        return
    fi
    
    # Verificar si hay distribuciones
    if [ "$distributions_json" = "null" ] || [ "$distributions_json" = "[]" ]; then
        success "✓ No se encontraron distribuciones CloudFront"
        echo "[]"
        return
    fi
    
    # Aplicar filtros si se especifican
    local filtered_json="$distributions_json"
    
    # Filtro por comentario/nombre
    if [ -n "$FILTER_PATTERN" ]; then
        filtered_json=$(echo "$distributions_json" | jq --arg pattern "$FILTER_PATTERN" '[.[] | select(.Comment // "" | contains($pattern))]' 2>/dev/null)
        if [ $? -ne 0 ]; then
            warn "Error aplicando filtro de patrón, usando datos sin filtrar"
            filtered_json="$distributions_json"
        fi
    fi
    
    # Filtro por estado
    if [ -n "$STATUS_FILTER" ]; then
        filtered_json=$(echo "$filtered_json" | jq --arg status "$STATUS_FILTER" '[.[] | select(.Status == $status)]' 2>/dev/null)
        if [ $? -ne 0 ]; then
            warn "Error aplicando filtro de estado, usando datos sin filtrar"
            filtered_json="$distributions_json"
        fi
    fi
    
    echo "$filtered_json"
}

# Mostrar tabla de distribuciones
show_distributions_table() {
    local distributions_json="$1"
    
    if [ "$distributions_json" = "[]" ] || [ -z "$distributions_json" ] || [ "$distributions_json" = "null" ]; then
        success "✓ No hay distribuciones que mostrar"
        return
    fi
    
    # Verificar que el JSON es válido
    local count
    count=$(echo "$distributions_json" | jq '. | length' 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$count" ]; then
        error "Error procesando datos de distribuciones para mostrar tabla"
        return
    fi
    
    if [ "$count" -eq 0 ]; then
        success "✓ No hay distribuciones que mostrar"
        return
    fi
    
    echo ""
    printf "%-18s %-12s %-8s %-30s %-40s\n" "ID" "STATUS" "ENABLED" "COMMENT" "DOMAIN"
    printf "%-18s %-12s %-8s %-30s %-40s\n" "------------------" "------------" "--------" "------------------------------" "----------------------------------------"
    
    echo "$distributions_json" | jq -r '.[] | [
        .Id, 
        .Status, 
        (.Enabled | tostring), 
        (.Comment // "Sin comentario" | if length > 28 then .[0:25] + "..." else . end),
        (.DomainName | if length > 38 then .[0:35] + "..." else . end)
    ] | @tsv' 2>/dev/null | while IFS=$'\t' read -r id status enabled comment domain; do
        printf "%-18s %-12s %-8s %-30s %-40s\n" "$id" "$status" "$enabled" "$comment" "$domain"
    done
}

# Deshabilitar distribución si está habilitada
disable_distribution() {
    local dist_id="$1"
    
    # Obtener configuración actual
    local config_response
    config_response=$(aws cloudfront get-distribution-config $REGION_FLAG --id "$dist_id" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        error "No se pudo obtener configuración de $dist_id"
        return 1
    fi
    
    local etag
    etag=$(echo "$config_response" | jq -r '.ETag' 2>/dev/null)
    
    local enabled
    enabled=$(echo "$config_response" | jq -r '.DistributionConfig.Enabled' 2>/dev/null)
    
    if [ "$enabled" = "true" ]; then
        log "  Distribución habilitada, deshabilitando..."
        
        # Crear configuración con Enabled=false
        local new_config
        new_config=$(echo "$config_response" | jq '.DistributionConfig | .Enabled = false' 2>/dev/null)
        
        # Guardar configuración temporalmente
        echo "$new_config" > "/tmp/dist_config_${dist_id}.json"
        
        execute_command "aws cloudfront update-distribution $REGION_FLAG --id \"$dist_id\" --distribution-config file:///tmp/dist_config_${dist_id}.json --if-match \"$etag\"" \
            "Deshabilitando distribución $dist_id"
        
        # Limpiar archivo temporal
        rm -f "/tmp/dist_config_${dist_id}.json"
        
        if [ "$DRY_RUN" = false ]; then
            log "  Esperando a que la distribución se despliegue..."
            aws cloudfront wait distribution-deployed $REGION_FLAG --id "$dist_id" 2>/dev/null || true
        fi
        
        return 0
    else
        log "  Distribución ya está deshabilitada"
        return 0
    fi
}

# Eliminar distribución
delete_distribution() {
    local dist_id="$1"
    local comment="$2"
    
    log "Procesando distribución: $dist_id"
    if [ -n "$comment" ] && [ "$comment" != "null" ]; then
        log "  Comentario: $comment"
    fi
    
    # Verificar estado actual
    local current_status
    current_status=$(aws cloudfront get-distribution $REGION_FLAG --id "$dist_id" --query 'Distribution.Status' --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        error "No se pudo obtener estado de $dist_id"
        return 1
    fi
    
    log "  Estado actual: $current_status"
    
    # Si no está en estado Deployed, no se puede eliminar
    if [ "$current_status" != "Deployed" ]; then
        warn "  ⚠️  Distribución no está en estado 'Deployed', saltando..."
        return 0
    fi
    
    # Deshabilitar si está habilitada
    if ! disable_distribution "$dist_id"; then
        error "No se pudo deshabilitar $dist_id"
        return 1
    fi
    
    # Obtener ETag para eliminación
    local etag
    etag=$(aws cloudfront get-distribution $REGION_FLAG --id "$dist_id" --query 'ETag' --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        error "No se pudo obtener ETag de $dist_id"
        return 1
    fi
    
    log "  ETag: $etag"
    
    # Eliminar distribución
    execute_command "aws cloudfront delete-distribution $REGION_FLAG --id \"$dist_id\" --if-match \"$etag\"" \
        "Eliminando distribución $dist_id"
    
    return 0
}

# Limpiar distribuciones
cleanup_distributions() {
    local distributions_json="$1"
    
    if [ "$distributions_json" = "[]" ] || [ -z "$distributions_json" ]; then
        success "✓ No hay distribuciones que eliminar"
        return
    fi
    
    # Obtener array de IDs y comentarios
    local dist_data
    dist_data=$(echo "$distributions_json" | jq -r '.[] | "\(.Id)|\(.Comment // "Sin comentario")"')
    
    local total_distributions
    total_distributions=$(echo "$distributions_json" | jq '. | length')
    
    log "🗑️  Iniciando eliminación de $total_distributions distribuciones..."
    
    local current=0
    while IFS='|' read -r dist_id comment; do
        current=$((current + 1))
        
        echo "----------------------------------------"
        log "[$current/$total_distributions] Procesando: $dist_id"
        
        delete_distribution "$dist_id" "$comment"
        
        # Pausa entre eliminaciones para evitar throttling
        if [ "$DRY_RUN" = false ] && [ $current -lt $total_distributions ]; then
            log "⏳ Esperando 3 segundos antes de continuar..."
            sleep 3
        fi
        
    done <<< "$dist_data"
}

# Mostrar resumen
show_summary() {
    echo ""
    echo "========================================"
    echo "📊 RESUMEN DE DISTRIBUCIONES ENCONTRADAS"
    echo "========================================"
    
    local distributions_json
    distributions_json=$(list_distributions)
    
    # Verificar si hay error en el JSON
    if [ -z "$distributions_json" ]; then
        error "No se pudieron obtener distribuciones"
        echo ""
        echo "========================================"
        return
    fi
    
    local count
    count=$(echo "$distributions_json" | jq '. | length' 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        error "Error procesando datos de distribuciones"
        echo ""
        echo "========================================"
        return
    fi
    
    # Verificar si count es un número válido
    if ! [[ "$count" =~ ^[0-9]+$ ]]; then
        error "Respuesta inválida del servicio CloudFront"
        echo ""
        echo "========================================"
        return
    fi
    
    if [ "$count" -gt 0 ]; then
        log "🌐 Total distribuciones encontradas: $count"
        show_distributions_table "$distributions_json"
    else
        success "✓ No se encontraron distribuciones que coincidan con los criterios"
    fi
    
    echo ""
    echo "========================================"
    
    # Devolver el JSON para uso posterior
    echo "$distributions_json"
}

# Función principal
main() {
    # Verificar dependencias
    command -v aws >/dev/null 2>&1 || { error "AWS CLI no está instalado"; exit 1; }
    command -v jq >/dev/null 2>&1 || { error "jq no está instalado"; exit 1; }
    
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
            --status)
                if [[ $# -lt 2 ]]; then
                    error "La opción --status requiere un valor"
                    exit 1
                fi
                STATUS_FILTER="$2"
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
    log "🚀 INICIANDO LIMPIEZA DE CLOUDFRONT"
    if [ -n "$REGION" ]; then
        log "🌍 Región (credenciales): $REGION"
    else
        log "🌍 Usando región por defecto del perfil AWS"
    fi
    if [ -n "$FILTER_PATTERN" ]; then
        log "🔍 Filtro: *$FILTER_PATTERN*"
    fi
    if [ -n "$STATUS_FILTER" ]; then
        log "📊 Estado: $STATUS_FILTER"
    fi
    if [ "$DRY_RUN" = true ]; then
        warn "MODO DRY-RUN: No se ejecutarán cambios reales"
    fi
    echo ""
    
    # Mostrar resumen y obtener distribuciones
    local distributions_json
    distributions_json=$(show_summary)
    
    # Confirmar antes de proceder (solo si no es dry-run y hay distribuciones)
    local count
    count=$(echo "$distributions_json" | jq '. | length' 2>/dev/null)
    
    if [ $? -ne 0 ] || ! [[ "$count" =~ ^[0-9]+$ ]]; then
        error "Error procesando datos para confirmación"
        exit 1
    fi
    
    if [ "$count" -gt 0 ]; then
        if [ "$DRY_RUN" = false ]; then
            echo ""
            read -p "¿Deseas proceder con la eliminación de $count distribuciones? (y/N): " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Operación cancelada por el usuario"
                exit 0
            fi
        fi
        
        # Ejecutar limpieza
        cleanup_distributions "$distributions_json"
    fi
    
    # Resumen final
    echo ""
    echo "========================================"
    if [ ${#ERRORS[@]} -eq 0 ]; then
        success "🎉 LIMPIEZA COMPLETADA EXITOSAMENTE"
        if [ "$DRY_RUN" = false ]; then
            log "📋 Verificar con: aws cloudfront list-distributions --query 'DistributionList.Items[*].[Id,Status,Comment]' --output table"
        fi
    else
        warn "⚠️  LIMPIEZA COMPLETADA CON ERRORES:"
        for error in "${ERRORS[@]}"; do
            echo -e "  ${RED}✗${NC} $error"
        fi
    fi
    echo "========================================"
}

# Ejecutar script principal
main "$@"