# AWS Cleanup Scripts

Una colección de scripts de bash para limpiar y auditar recursos de AWS de manera automatizada.

## Scripts Incluidos

- **aws_resources_audit_script.sh** - Script de auditoría de recursos AWS
- **cleanup_ami_snapshots.sh** - Limpieza de AMIs y snapshots
- **delete_api_gateways.sh** - Eliminación de API Gateways
- **delete_cloudformation_stacks.sh** - Eliminación de stacks de CloudFormation
- **delete_cloudfront_script.sh** - Limpieza de distribuciones CloudFront
- **delete_ebs_volumes.sh** - Eliminación de volúmenes EBS
- **delete_waf_script.sh** - Eliminación de recursos WAF
- **vpc_cleanup_script.sh** - Limpieza de VPCs y recursos relacionados

## Requisitos

- AWS CLI instalado y configurado
- Permisos apropiados en AWS para los recursos que deseas limpiar
- Bash shell

## Uso

1. Clona el repositorio:
```bash
git clone https://github.com/luismalamoc/aws_cleanup_bash_scripts.git
cd aws_cleanup_bash_scripts
```

2. Haz los scripts ejecutables:
```bash
chmod +x *.sh
```

3. Ejecuta el script que necesites:
```bash
./nombre_del_script.sh
```

## ⚠️ Advertencia

Estos scripts eliminan recursos de AWS. **Úsalos con precaución** y siempre en entornos de prueba primero. Asegúrate de entender qué hace cada script antes de ejecutarlo en producción.

## Contribuir

Las contribuciones son bienvenidas. Por favor, abre un issue o envía un pull request.

## Licencia

Este proyecto está bajo la licencia MIT.
