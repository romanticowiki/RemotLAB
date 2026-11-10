# Configuración de RemotLAB con Ansible

`site.yml` configura la instancia creada por Terraform. Los secretos viven exclusivamente en
`inventory/group_vars/lab/secrets.yml`, archivo ignorado por Git. Usa
`secrets.example.yml` como plantilla.

## Roles

| Rol | Responsabilidad |
|---|---|
| `base` | Paquetes base, XFCE, TigerVNC y swap |
| `tuning_host` | Límites, rotación de logs y ajustes opcionales del host |
| `usuarios` | Usuarios Linux y credenciales locales |
| `compartido` | Directorios de reparto y entregas |
| `gns3` | GNS3 y rangos de puertos por usuario |
| `vnc` | Sesiones gráficas y servicios systemd |
| `docker_stack` | Guacamole, `guacd`, MariaDB y perfiles del proxy |
| `caddy` | Validación y activación de Caddy |
| `api` | API de métricas, sesiones y acceso supervisado |

## Preparación

```bash
cp inventory/group_vars/lab/secrets.example.yml \
   inventory/group_vars/lab/secrets.yml
```

Configura también `inventory/hosts.yml` con tu dominio y llave SSH. El nombre público debe
coincidir con `lab_fqdn` en `group_vars/lab/main.yml` y en `terraform.tfvars`.

## Ejecución

```bash
ansible-playbook site.yml
```

Por fases:

```bash
ansible-playbook site.yml --tags base,tuning
ansible-playbook site.yml --tags usuarios,compartido,gns3,vnc
ansible-playbook site.yml --tags docker,caddy,api
```

El playbook comprueba nombres, displays y rangos de puertos duplicados antes de modificar el host.

## Añadir una persona

1. Añade una entrada a `usuarios_lab` en `inventory/group_vars/lab/main.yml`.
2. Añade sus contraseñas Linux y VNC al archivo local `secrets.yml`.
3. Ejecuta `ansible-playbook site.yml`.

Las conexiones de Guacamole se generan desde `usuarios_lab`; no es necesario publicar un volcado
de base de datos.

## Validación sin servidor

```bash
python3 tests/validar_optimizacion.py
ansible-playbook -i 'localhost,' --syntax-check site.yml
```

Para medir idempotencia sin que una actualización de paquetes altere el resultado:

```bash
ansible-playbook site.yml -e hacer_upgrade=false
ansible-playbook site.yml -e hacer_upgrade=false
```

La segunda ejecución debe terminar sin cambios salvo que el entorno externo haya variado.
