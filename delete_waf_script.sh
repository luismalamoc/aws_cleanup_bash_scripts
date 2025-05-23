#!/bin/bash

# Script para eliminar WAF Web ACLs de CloudFront
# Uso: ./delete_waf_cloudfront.sh [region]
# Ejemplo: ./delete_waf_cloudfront.sh us-east-1
# Nota: Los Web ACLs de CloudFront siempre se manejan desde us-east-1

# Verificar si se proporcionó una región
if [ $# -eq 1 ]; then
    REGION=$1
    echo "🌍 Región solicitada: $REGION"
else
    REGION="us-east-1"
    echo "🌍 Usando región por defecto: $REGION"
fi

# IMPORTANTE: CloudFront Web ACLs SIEMPRE deben manejarse desde us-east-1
CLOUDFRONT_REGION="us-east-1"

if [ "$REGION" != "us-east-1" ]; then
    echo "⚠️  AVISO: Los Web ACLs de CloudFront siempre se manejan desde us-east-1"
    echo "    Cambiando automáticamente a us-east-1 para esta operación"
    REGION=$CLOUDFRONT_REGION
fi

echo "🗑️ Eliminando WAF Web ACLs de CloudFront desde región: $REGION"
echo "============================================================"

# Obtener lista completa de Web ACLs con ID y Name
aws wafv2 list-web-acls --region $REGION --scope CLOUDFRONT --query 'WebACLs[*].[Id,Name]' --output text | \
while IFS=$'\t' read -r web_acl_id web_acl_name; do
    if [ ! -z "$web_acl_id" ] && [ ! -z "$web_acl_name" ]; then
        echo "Eliminando Web ACL: $web_acl_name (ID: $web_acl_id)"
        
        # Obtener lock token con ID y Name
        lock_token=$(aws wafv2 get-web-acl --region $REGION --scope CLOUDFRONT --id "$web_acl_id" --name "$web_acl_name" --query 'LockToken' --output text 2>/dev/null)
        
        if [ ! -z "$lock_token" ] && [ "$lock_token" != "None" ]; then
            # Intentar eliminar con ID, Name y Lock Token
            if aws wafv2 delete-web-acl --region $REGION --scope CLOUDFRONT --id "$web_acl_id" --name "$web_acl_name" --lock-token "$lock_token" 2>/dev/null; then
                echo "✅ Web ACL $web_acl_name eliminado exitosamente"
            else
                echo "❌ Error eliminando Web ACL $web_acl_name - podría estar asociado a una distribución"
                echo "   Verificando asociaciones..."
                
                # Verificar si está asociado a alguna distribución
                associated_distributions=$(aws cloudfront list-distributions --query "DistributionList.Items[?WebACLId=='$web_acl_id'].[Id,DomainName]" --output text)
                if [ ! -z "$associated_distributions" ]; then
                    echo "   🔗 Asociado a distribuciones:"
                    echo "$associated_distributions" | while read dist_id domain; do
                        echo "      - $domain (ID: $dist_id)"
                    done
                    echo "   💡 Desasocia el Web ACL de las distribuciones antes de eliminarlo"
                fi
            fi
        else
            echo "⚠️  No se pudo obtener lock token para $web_acl_name"
            echo "   Esto puede indicar que el Web ACL no existe o no tienes permisos"
        fi
        echo "---"
    fi
done

echo "🎉 Proceso completado"
echo ""
echo "📋 Para verificar Web ACLs restantes, ejecuta:"
echo "   aws wafv2 list-web-acls --region $REGION --scope CLOUDFRONT --query 'WebACLs[*].[Name,Id]' --output table"