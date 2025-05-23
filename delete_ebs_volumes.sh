#!/bin/bash

# Script para eliminar volúmenes EBS disponibles
# Uso: ./delete_ebs_volumes.sh <region>

REGION=$1

# Validar que se proporcione la región
if [ -z "$REGION" ]; then
    echo "Error: Debes proporcionar la región como parámetro"
    echo "Uso: $0 <region>"
    echo "Ejemplo: $0 us-east-1"
    exit 1
fi

# Función para mostrar información de los volúmenes
show_volumes() {
    echo "📦 Consultando volúmenes EBS en región: $REGION"
    echo "=============================================="
    
    # Obtener volúmenes disponibles
    aws ec2 describe-volumes \
        --region "$REGION" \
        --filters "Name=status,Values=available" \
        --query 'Volumes[*].[VolumeId,Size,VolumeType,State,Tags[?Key==`Name`].Value|[0]]' \
        --output table
}

# Función para obtener IDs de volúmenes disponibles
get_available_volumes() {
    aws ec2 describe-volumes \
        --region "$REGION" \
        --filters "Name=status,Values=available" \
        --query 'Volumes[*].VolumeId' \
        --output text
}

# Función para eliminar un volumen
delete_volume() {
    local volume_id=$1
    
    echo "Eliminando volumen: $volume_id..."
    
    # Intentar eliminar el volumen
    if aws ec2 delete-volume --volume-id "$volume_id" --region "$REGION" 2>/dev/null; then
        echo "✅ Volumen $volume_id eliminado exitosamente"
    else
        echo "❌ Error al eliminar volumen $volume_id"
        
        # Verificar el estado del volumen
        local state=$(aws ec2 describe-volumes \
            --volume-ids "$volume_id" \
            --region "$REGION" \
            --query 'Volumes[0].State' \
            --output text 2>/dev/null)
        
        if [ "$state" != "None" ] && [ ! -z "$state" ]; then
            echo "   Estado actual: $state"
            if [ "$state" = "in-use" ]; then
                echo "   El volumen está en uso y no puede eliminarse"
            fi
        else
            echo "   El volumen no existe o ya fue eliminado"
        fi
    fi
    echo ""
}

# Mostrar volúmenes disponibles
show_volumes

# Obtener lista de volúmenes disponibles
AVAILABLE_VOLUMES=$(get_available_volumes)

if [ -z "$AVAILABLE_VOLUMES" ]; then
    echo "ℹ️  No se encontraron volúmenes EBS disponibles en la región $REGION"
    exit 0
fi

# Contar volúmenes
VOLUME_COUNT=$(echo "$AVAILABLE_VOLUMES" | wc -w)
echo ""
echo "🗑️  Se encontraron $VOLUME_COUNT volúmenes disponibles para eliminar"
echo ""

# Mostrar volúmenes que serán eliminados
echo "Volúmenes que serán eliminados:"
for volume_id in $AVAILABLE_VOLUMES; do
    echo "• $volume_id"
done
echo ""

# Confirmación antes de proceder
read -p "¿Estás seguro de que quieres eliminar TODOS estos volúmenes? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operación cancelada."
    exit 0
fi

echo ""
echo "Iniciando eliminación de volúmenes..."
echo "====================================="

# Eliminar cada volumen
for volume_id in $AVAILABLE_VOLUMES; do
    delete_volume "$volume_id"
done

echo "====================================="
echo "✨ Proceso completado"

# Verificar volúmenes restantes
echo ""
echo "Verificando volúmenes EBS restantes disponibles..."
show_volumes