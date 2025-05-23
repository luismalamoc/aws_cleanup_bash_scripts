#!/bin/bash

# Script para eliminar TODOS los CloudFormation Stacks problemáticos
# Uso: ./delete_cloudformation_stacks.sh [region]
# Ejemplo: ./delete_cloudformation_stacks.sh us-east-1

# Verificar si se proporcionó una región
if [ $# -eq 1 ]; then
    REGION=$1
    echo "🌍 Usando región: $REGION"
    REGION_FLAG="--region $REGION"
else
    echo "🌍 Usando región por defecto del perfil AWS"
    REGION_FLAG=""
fi

echo "🗑️ ELIMINANDO TODOS LOS CLOUDFORMATION STACKS PROBLEMÁTICOS"
echo "============================================================="
echo "Fecha: $(date)"
echo ""

# Función para eliminar stack sin confirmación
delete_stack_force() {
    local stack_name=$1
    local stack_status=$2
    
    echo "🗑️ Eliminando: $stack_name (Estado: $stack_status)"
    
    case $stack_status in
        "DELETE_FAILED")
            echo "   📋 Estrategia: DELETE_FAILED - Intentando continuar rollback primero"
            aws cloudformation continue-update-rollback $REGION_FLAG --stack-name "$stack_name" 2>/dev/null
            sleep 5
            aws cloudformation delete-stack $REGION_FLAG --stack-name "$stack_name" 2>/dev/null
            ;;
        "CREATE_FAILED"|"ROLLBACK_COMPLETE"|"ROLLBACK_FAILED"|"UPDATE_ROLLBACK_COMPLETE"|"UPDATE_ROLLBACK_FAILED")
            echo "   📋 Estrategia: Eliminación directa para estado $stack_status"
            aws cloudformation delete-stack $REGION_FLAG --stack-name "$stack_name" 2>/dev/null
            ;;
        *)
            echo "   📋 Estrategia: Eliminación estándar para estado $stack_status"
            aws cloudformation delete-stack $REGION_FLAG --stack-name "$stack_name" 2>/dev/null
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo "   ✅ Comando enviado exitosamente"
    else
        echo "   ⚠️  Posible error - continuando con el siguiente"
    fi
    echo "---"
}

# Consultar stacks problemáticos
echo "🔍 CONSULTANDO STACKS PROBLEMÁTICOS..."
problem_stacks=$(aws cloudformation list-stacks $REGION_FLAG \
    --stack-status-filter DELETE_FAILED CREATE_FAILED ROLLBACK_COMPLETE ROLLBACK_FAILED UPDATE_ROLLBACK_COMPLETE UPDATE_ROLLBACK_FAILED \
    --query 'StackSummaries[*].[StackName,StackStatus]' --output text)

if [ -z "$problem_stacks" ]; then
    echo "✅ No se encontraron stacks problemáticos para eliminar"
    exit 0
fi

# Contar y mostrar resumen
total_stacks=$(echo "$problem_stacks" | wc -l)
echo "📊 ENCONTRADOS: $total_stacks stacks problemáticos"
echo ""
echo "📋 LISTA DE STACKS A ELIMINAR:"
echo "$problem_stacks" | while IFS=$'\t' read -r stack_name stack_status; do
    echo "   $stack_status: $stack_name"
done
echo ""

echo "🚀 INICIANDO ELIMINACIÓN AUTOMÁTICA (SIN CONFIRMACIONES)"
echo "========================================================"

# Crear array temporal para evitar problemas con subshell
temp_file=$(mktemp)
echo "$problem_stacks" > "$temp_file"

# Procesar cada stack
while IFS=$'\t' read -r stack_name stack_status; do
    if [ ! -z "$stack_name" ] && [ ! -z "$stack_status" ]; then
        delete_stack_force "$stack_name" "$stack_status"
    fi
done < "$temp_file"

# Limpiar archivo temporal
rm -f "$temp_file"

echo "⏳ ESPERANDO UN MOMENTO PARA VERIFICAR RESULTADOS..."
sleep 10

echo ""
echo "🔍 VERIFICANDO STACKS RESTANTES..."
remaining_stacks=$(aws cloudformation list-stacks $REGION_FLAG \
    --stack-status-filter DELETE_FAILED CREATE_FAILED ROLLBACK_COMPLETE ROLLBACK_FAILED UPDATE_ROLLBACK_COMPLETE UPDATE_ROLLBACK_FAILED \
    --query 'StackSummaries[*].[StackName,StackStatus]' --output text)

if [ -z "$remaining_stacks" ]; then
    echo "🎉 ¡TODOS LOS STACKS PROBLEMÁTICOS HAN SIDO ELIMINADOS!"
else
    remaining_count=$(echo "$remaining_stacks" | wc -l)
    echo "⚠️  AÚN QUEDAN $remaining_count STACKS PROBLEMÁTICOS:"
    echo "$remaining_stacks" | while IFS=$'\t' read -r stack_name stack_status; do
        echo "   $stack_status: $stack_name"
    done
    echo ""
    echo "💡 Algunos stacks pueden tardar varios minutos en eliminarse completamente"
    echo "💡 Para stacks persistentes, verifica dependencias en la consola AWS"
fi

echo ""
echo "🎉 PROCESO COMPLETADO"
echo "===================="
echo ""
echo "📋 Para verificar el estado actual de todos los stacks:"
echo "   aws cloudformation list-stacks $REGION_FLAG --query 'StackSummaries[*].[StackName,StackStatus]' --output table"
echo ""
echo "💡 NOTAS IMPORTANTES:"
echo "   - Los comandos de eliminación fueron enviados para todos los stacks"
echo "   - Algunos pueden tardar varios minutos en eliminarse completamente"
echo "   - Los stacks ECS con dependencias pueden requerir intervención manual"
echo "   - Si un stack persiste, verifica en la consola AWS las dependencias"