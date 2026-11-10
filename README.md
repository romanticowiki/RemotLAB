# RemotLAB · Aula Remota

Plataforma para ofrecer laboratorios de redes con GNS3 desde un navegador. El trabajo pesado
se ejecuta en AWS; cada estudiante recibe un escritorio Linux aislado y puede entrar desde un
equipo modesto sin instalar GNS3 localmente.

El repositorio reúne la infraestructura reproducible, la configuración del servidor, una API de
supervisión y una app Flutter para docentes y administradores.

## Qué resuelve

- Despliega la red, reglas de acceso y una instancia EC2 con Terraform.
- Configura usuarios, escritorios XFCE, TigerVNC y GNS3 con Ansible.
- Publica los escritorios mediante Apache Guacamole y `guacd`.
- Ejecuta Guacamole, MariaDB y el proxy TLS con Docker Compose.
- Expone métricas y sesiones mediante una API local de solo lectura.
- Permite supervisar el laboratorio desde Android con la app Flutter incluida.

## Arquitectura

```text
Navegador o app Flutter
        │ HTTPS
        ▼
Nginx Proxy Manager o Caddy
        ▼
Apache Guacamole ── guacd ── TigerVNC ── XFCE ── GNS3
        │
        └── MariaDB

Terraform ──> AWS
Ansible   ──> host, usuarios, servicios y contenedores
```

La arquitectura usa una sola instancia EC2 a propósito. Para un laboratorio pequeño, separar
los componentes aumentaría el costo y la complejidad sin mejorar el resultado educativo.

## Tecnologías

| Capa | Tecnologías |
|---|---|
| Infraestructura | Terraform, AWS VPC, EC2, EBS y Security Groups |
| Configuración | Ansible |
| Escritorios | TigerVNC, XFCE4 y GNS3 2.2 |
| Acceso web | Apache Guacamole y `guacd` |
| Servicios | Docker Compose y MariaDB |
| Proxy TLS | Nginx Proxy Manager o Caddy |
| Supervisión | API Python sin dependencias externas |
| Aplicación móvil | Flutter, WebView y autenticación biométrica del dispositivo |

## Estructura

```text
.
├── *.tf                         infraestructura AWS
├── terraform.tfvars.example    configuración pública de ejemplo
├── ansible/
│   ├── site.yml                playbook principal
│   ├── inventory/              host, usuarios y plantilla de secretos
│   ├── roles/                  host, GNS3, VNC, Docker, proxy y API
│   └── tests/                  validaciones locales
├── app_movil/                  aplicación Flutter de supervisión
└── website/                    landing estática
```

## Preparación

Requisitos:

- Terraform 1.5 o posterior.
- AWS CLI con un perfil autorizado.
- Ansible en Linux o WSL.
- Docker Compose se instala en la instancia mediante Ansible.
- Flutter estable para compilar la app móvil.

Crea primero los archivos locales que el repositorio excluye:

```bash
cp terraform.tfvars.example terraform.tfvars
cp ansible/inventory/group_vars/lab/secrets.example.yml \
   ansible/inventory/group_vars/lab/secrets.yml
```

Después configura el dominio, el key pair, el CIDR administrativo y los secretos de tu propio
despliegue. No uses los valores de ejemplo en producción.

## Despliegue

```bash
terraform init
terraform apply

cd ansible
ansible-playbook site.yml
```

El objetivo es que una instalación nueva pueda reconstruirse con esos dos pasos. Consulta
[`ansible/README.md`](ansible/README.md) para las validaciones y despliegues parciales.

## App móvil

La aplicación está en [`app_movil/`](app_movil/). Desde Ajustes recibe la URL del servidor y
un token generado para esa instancia. No contiene credenciales predefinidas.

```bash
cd app_movil
flutter pub get
flutter analyze
flutter test
flutter build apk
```

La biometría permanece en el sistema operativo. La aplicación solo recibe el resultado de la
verificación y conserva un PIN de respaldo protegido con sal local.

## Seguridad

- `terraform.tfvars`, estados, planes, llaves privadas y `secrets.yml` están ignorados.
- El repositorio solo incluye plantillas sin valores reales.
- Los puertos VNC no deben exponerse a Internet.
- La API y Guacamole deben publicarse detrás de HTTPS en producción.
- El modo HTTP y los puertos 8000/8080 existen únicamente para pruebas controladas.

Si una credencial llega al historial Git, añadirla después a `.gitignore` no la protege: hay que
revocarla y limpiar el historial.

## Validación local

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate

python3 ansible/tests/validar_optimizacion.py
cd ansible && ansible-playbook -i 'localhost,' --syntax-check site.yml
```

## Limitaciones conocidas

- `t3.micro` permite validar infraestructura, pero no tiene memoria suficiente para un aula con
  varios escritorios y GNS3. Para uso real se necesita una instancia con aproximadamente 8 GiB.
- MariaDB 10.5 se conserva por compatibilidad con el conjunto probado, aunque está fuera de
  soporte. La migración debe validarse antes de cambiar el digest.
- Nginx Proxy Manager permanece como opción inicial; Caddy está preparado como migración y
  alternativa de reversión.
- La seguridad final depende de usar secretos únicos, restringir `admin_cidr` y cerrar los puertos
  de prueba después de habilitar HTTPS.

## Estado

Proyecto académico en desarrollo. Su propósito es demostrar una infraestructura reproducible y
una experiencia de acceso remoto, no ofrecer un servicio administrado listo para producción.

