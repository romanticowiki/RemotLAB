# Aula Remota — App administrativa

App móvil de supervisión del laboratorio. Lee el estado **real** de la
instancia: recursos, servicios, escritorios y alertas. Y desde la pestaña
**Sesiones** abre el escritorio de cualquier alumno, igual que lo haría el
maestro desde Guacamole.

Los endpoints de métricas son de **solo lectura**: ninguno reinicia, borra ni
modifica nada del servidor.

---

## Ver el escritorio de un alumno

En **Sesiones**, cada conexión tiene un botón:

| Estado | Botón |
|---|---|
| El alumno está conectado | **Ver lo que está haciendo** |
| Escritorio libre pero encendido | **Abrir el escritorio** |
| El puerto VNC no responde | deshabilitado, *"El escritorio no responde"* |

### Se abre observando, no controlando

Al entrar, la vista **no acepta toques**. Guacamole da control real de teclado
y ratón, y un roce accidental movería el ratón del alumno en mitad de su
examen. Para tomar el control hay que pulsar **Controlar**, y aparece un aviso
que dice quién está usando ese escritorio ahora mismo.

### El alumno no pierde su sesión

El servidor VNC arranca con `-AlwaysShared` (rol `vnc` de Ansible). Sin esa
bandera TigerVNC expulsa al visor anterior cuando entra uno nuevo: abrir el
escritorio desde el móvil echaría al alumno de su propia clase. Con ella los
dos ven la misma pantalla a la vez.

### Cómo funciona por dentro

La app **no implementa VNC**. Guacamole ya resuelve el problema entero —RFB,
compresión, escalado, teclado, portapapeles, reconexión—, así que la app carga
el mismo portal que usa el maestro desde el navegador, dentro de un `WebView`,
con la sesión ya iniciada:

1. La app pide `GET /api/v1/escritorio?conexion=PC-Alumno-1`
2. La API busca el `connection_id` en MariaDB
3. La API se autentica contra Guacamole como el usuario `supervisor`
4. La API devuelve la URL del cliente, ya firmada
5. La app la carga en el `WebView`

**La contraseña de Guacamole nunca llega al teléfono.** Si alguien descompila
el APK, ahí no hay credenciales del laboratorio.

Y `supervisor` **no es `guacadmin`**: un token de Guacamole no distingue entre
"ver un escritorio" y "administrar Guacamole", es la sesión entera. Si la API
pidiera el token como `guacadmin`, cualquiera con el token de la API tendría
de hecho el panel completo. `supervisor` solo tiene permiso `READ` sobre las
conexiones.

---

## Bloqueo de la app

En **Ajustes → Seguridad**. Funciona como una app de banco: huella o rostro,
con PIN de respaldo.

### La app nunca ve tu huella

Le pide al sistema operativo que valide a quien tenga el teléfono en la mano y
recibe un sí o un no. El dato biométrico se queda dentro del enclave seguro del
chip. Lo único que guarda la app es un booleano que dice si hay que preguntar.

### Siempre hay PIN, y se define primero

La huella falla: dedos mojados, pantalla rota, sensor sucio, o un teléfono que
no tiene sensor. Si la biometría fuera el único camino, un sensor averiado
dejaría el laboratorio inaccesible desde el móvil. Por eso el PIN se define
**antes** de ofrecer la huella. Es el mismo orden que usan los bancos.

| Detalle | Por qué |
|---|---|
| Se pide dos veces al crearlo | Un PIN mal tecleado una vez deja la app inaccesible con un código que nadie conoce |
| Rechaza `111111` y `123456` | Se adivinan mirando el rastro de dedos en la pantalla |
| Guardado como SHA-256 con sal por dispositivo | Sin sal, un millón de combinaciones se precalculan en segundos, y la tabla valdría para cualquier teléfono |
| 3 fallos → espera creciente (15 s, 30 s, 60 s…) | Frena el tanteo sin dejar al dueño fuera para siempre |
| Teclado propio, no el de Android | El del sistema ocupa media pantalla, sugiere y deja el PIN a un portapapeles de distancia |
| No vuelve a pedir si sales menos de 30 s | Mirar una notificación y volver no debería costar otra huella; si molesta, se desactiva |

El bloqueo tapa **también** la pantalla de Ajustes, que es donde se ve y se
edita el token del servidor.

> Esto protege frente a alguien que toma el teléfono desbloqueado. No frente a
> un análisis forense del dispositivo: de eso se encarga el cifrado de Android.

---

## Cómo conectarla

Al abrirla por primera vez pide dos datos:

| Campo | Valor |
|---|---|
| Dirección del servidor | `https://lab.example.com` |
| Token de acceso | el `api_token` de `ansible/inventory/group_vars/lab/secrets.yml` |

Se guardan solo en el teléfono (`SharedPreferences`). El token viaja en la
cabecera `Authorization: Bearer`.

Para verlo:

```bash
grep '^api_token:' ansible/inventory/group_vars/lab/secrets.yml
```

---

## Conectarla a OTRA instancia (la de tu compañero)

**No hay que tocar ni una línea de la app.** Todo es configurable desde la
pantalla de ajustes.

Lo que tiene que hacer el dueño de la otra instancia:

### 1. Traer el repo con el rol `api`

```bash
git pull
```

### 2. Generar su propio token

```bash
openssl rand -base64 32
```

Y añadirlo a su `ansible/inventory/group_vars/lab/secrets.yml`:

```yaml
api_token: "el-que-acaba-de-generar"
```

> Cada instancia debe tener **su propio token**. Compartirlo significa que
> quien pueda leer una puede leer la otra.

### 3. Desplegar la API

```bash
cd ansible
ansible-playbook site.yml --tags api
```

El rol instala un servicio systemd, comprueba que responde, y verifica que
sin token devuelve 401. Si algo falla, aborta con el motivo.

### 4. Abrir los DOS puertos

En su `terraform.tfvars`:

```hcl
api_expuesta       = true   # 8000, los datos
guacamole_expuesto = true   # 8080, el escritorio remoto
```

Y en `group_vars/lab/main.yml`, `guacamole_expuesto: true` también: uno abre
el security group y el otro hace que el contenedor escuche fuera de loopback.
Con cualquiera de los dos en `false` el escritorio remoto no funciona, y el
síntoma —pantalla en blanco en el móvil— no apunta a la causa.

```bash
terraform apply
```

### 5. En la app

Ajustes → poner `http://SU_IP_PUBLICA:8000` y su token → **Guardar y probar**.

El puerto 8080 no se teclea en ningún lado: la API se lo dice sola a la app,
deduciendo el host de la cabecera `Host` de la propia petición.

La app prueba la conexión antes de guardar: si el token está mal o el
servidor no responde, lo dice con el motivo concreto en vez de guardar una
configuración rota.

---

## Qué necesita la instancia para que la app funcione

Nada especial. El rol `api` usa **solo la biblioteca estándar de Python 3**,
que Ubuntu 22.04 ya trae. No instala paquetes, no usa pip, no añade
contenedores.

Lee de:

| Dato | De dónde sale |
|---|---|
| CPU | `/proc/stat`, calculado como delta entre lecturas |
| Memoria y swap | `/proc/meminfo` |
| Disco | `statvfs` sobre `/` |
| Red | `/proc/net/dev` |
| Servicios | `docker inspect` de los 4 contenedores |
| Escritorios | units `vncserver-*` y puertos 5901-5909 |
| Sesiones activas | `guacamole_connection_history` con `end_date IS NULL` |

Esa última es la misma fuente que usa el panel de Guacamole, así que los
números **coinciden con lo que ve el administrador en la web**.

---

## Deuda conocida: el token viaja sin cifrar

Mientras la app hable con `http://IP:8000`, el token va en claro. Quien
capture el tráfico podría leer métricas — nunca modificar nada, porque la API
no expone ninguna operación de escritura.

**Cómo cerrarlo** (10 minutos, cuando haya tiempo):

1. En Nginx Proxy Manager (puerto 81), en el proxy host de
   `lab.example.com`, pestaña **Custom locations**:
   - Location: `/api/`
   - Forward: `http://10.0.77.58:8000`
2. Emitir el certificado Let's Encrypt para ese host.
3. En `terraform.tfvars`: `api_expuesta = false` y `terraform apply`.
4. En la app: cambiar el servidor a `https://lab.example.com`.
5. Borrar `android/app/src/main/res/xml/network_security_config.xml` y la
   línea `android:networkSecurityConfig` del `AndroidManifest.xml`.

A partir de ahí el puerto 8000 queda cerrado a internet y todo va por el 443
con TLS.

---

## Estructura del código

Cuatro ficheros. El corte no es por capas abstractas sino por lo único que
obliga: `bloqueo.dart` y `escritorio.dart` necesitan los colores y el cliente
de la API, y si esos vivieran en `main.dart` se formaría una importación
circular. Por eso están en `nucleo.dart`, que `main.dart` reexporta.

| Fichero | Qué hay |
|---|---|
| `nucleo.dart` | `C`, `Tono`, `Api`, `ApiError`, `Ajustes` |
| `main.dart` | Las cuatro pestañas, la configuración y el arranque |
| `bloqueo.dart` | Desbloqueo por biometría, teclado de PIN, creación de PIN |
| `escritorio.dart` | Vista web del escritorio remoto |

Piezas clave:

| Clase | Qué hace |
|---|---|
| `Tono` | `ThemeExtension` con los colores de estado. Un color significa lo mismo en toda la app y en los dos temas |
| `Api` | Cliente HTTP. Convierte cada fallo en un `ApiError` con mensaje y pista accionable |
| `Ajustes` | Servidor, token, tema, frecuencia y bloqueo, persistidos |
| `Panel` | Las cuatro pestañas, con refresco automático |
| `Biometria` | Envuelve `local_auth` y traduce sus errores a algo accionable |
| `PantallaEscritorio` | `WebView` sobre Guacamole, con modo observar |

El manejo de errores distingue los casos que el usuario puede resolver:
token inválido, servidor caído, respuesta no válida. Cada uno con su pista.

Si la conexión se cae con datos ya cargados, la app **no se vacía**: sigue
mostrando lo último bueno con un aviso de que está desactualizado.
