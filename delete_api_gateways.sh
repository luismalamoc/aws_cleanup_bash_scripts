#!/bin/bash

# Script para eliminar API Gateways V2
# Uso: ./delete_gateways.sh <region>

REGION=$1

# Validar que se proporcione la región
if [ -z "$REGION" ]; then
    echo "Error: Debes proporcionar la región como parámetro"
    echo "Uso: $0 <region>"
    echo "Ejemplo: $0 us-east-1"
    exit 1
fi

# IDs de los API Gateways a eliminar
GATEWAY_IDS=(
    "0b3f8r5ux4"
    "2klsnor7gc" 
    "3ifv1a8pae"
    "oqz7m6watc"
)

# Nombres correspondientes para referencia
GATEWAY_NAMES=(
    "batchExtractorTest-API"
    "StreamingFunction-API"
    "TestFunction-API"
    "kafkaRest-API"
)

echo "🗑️  API Gateways V2 a eliminar en región: $REGION"
echo "=================================================="
for i in "${!GATEWAY_IDS[@]}"; do
    echo "• ${GATEWAY_NAMES[$i]} (${GATEWAY_IDS[$i]})"
done
echo ""

# Confirmación antes de proceder
read -p "¿Estás seguro de que quieres eliminar estos gateways? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operación cancelada."
    exit 0
fi

echo ""
echo "Iniciando eliminación..."
echo "=================================================="

# Función para eliminar un gateway
delete_gateway() {
    local gateway_id=$1
    local gateway_name=$2
    
    echo "Eliminando $gateway_name (ID: $gateway_id)..."
    
    # Intentar eliminar el gateway
    if aws apigatewayv2 delete-api --api-id "$gateway_id" --region "$REGION" 2>/dev/null; then
        echo "✅ $gateway_name eliminado exitosamente"
    else
        echo "❌ Error al eliminar $gateway_name"
        echo "   Verificando si existe..."
        
        # Verificar si el gateway existe
        if aws apigatewayv2 get-api --api-id "$gateway_id" --region "$REGION" >/dev/null 2>&1; then
            echo "   El gateway existe pero no se pudo eliminar"
        else
            echo "   El gateway no existe o ya fue eliminado"
        fi
    fi
    echo ""
}

# Eliminar cada gateway
for i in "${!GATEWAY_IDS[@]}"; do
    delete_gateway "${GATEWAY_IDS[$i]}" "${GATEWAY_NAMES[$i]}"
done

echo "=================================================="
echo "✨ Proceso completado"

# Verificar gateways restantes
echo "Verificando API Gateways restantes..."
aws apigatewayv2 get-apis --region "$REGION" --query 'Items[*].[ApiId,Name,ProtocolType,CreatedDate,ApiEndpoint]' --output table