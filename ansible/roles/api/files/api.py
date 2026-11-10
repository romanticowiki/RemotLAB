#!/usr/bin/env python3
"""
API de supervision de Aula Remota.

Expone en solo-lectura lo que la app movil necesita: recursos del servidor,
estado de los servicios, sesiones activas y alertas derivadas.

POR QUE SIN DEPENDENCIAS
------------------------
Usa unicamente la biblioteca estandar de Python 3. Nada de FastAPI, Flask ni
pip. Tres motivos:

  1. La instancia es t3.micro (1 GiB). Instalar un framework con sus
     dependencias compiladas consume memoria y tiempo de arranque que aqui
     hacen falta para los escritorios.
  2. Cero superficie de suministro: no hay paquetes de terceros que auditar
     ni que se rompan al actualizar.
  3. Ubuntu 22.04 ya trae Python 3.10. El rol no instala nada.

SEGURIDAD
---------
  - Todo endpoint salvo /salud exige "Authorization: Bearer <token>".
  - La comparacion del token es en tiempo constante (hmac.compare_digest).
  - No devuelve contrasenas, ni llaves, ni el contenido de la base.

  - Los endpoints de metricas son de SOLO LECTURA: ninguno reinicia, borra ni
    modifica nada.

  - LA EXCEPCION, y hay que tenerla presente: /api/v1/escritorio pide a
    Guacamole una sesion en nombre del usuario "supervisor" y devuelve la URL
    ya autenticada. Eso convierte el token de la API en la llave para ver
    cualquier escritorio del laboratorio.
    Se acota de dos formas:
      * "supervisor" NO es guacadmin. Solo tiene permiso READ sobre las
        conexiones: no puede crear usuarios, ni cambiar contrasenas, ni tocar
        la configuracion de Guacamole.
      * La contrasena de guacadmin nunca sale de la instancia. La app no la
        conoce ni la necesita.
    Aun asi, mientras el puerto viaje en claro esto es lo mas sensible que
    expone la API. Es la razon de peso para ponerla detras del proxy TLS en
    cuanto se pueda.
"""

import base64
import hmac
import json
import os
import re
import shutil
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ.get("AR_API_HOST", "127.0.0.1")
PORT = int(os.environ.get("AR_API_PORT", "8000"))
TOKEN = os.environ.get("AR_API_TOKEN", "")
LIMITE_SESIONES = int(os.environ.get("AR_LIMITE_SESIONES", "4"))
BASE_GUAC = os.environ.get("AR_MYSQL_DATABASE", "guacamole_db")

# Guacamole. INTERNA es por donde la API le habla (loopback del host, porque el
# contenedor publica 8080). PUERTO_PUBLICO es el que tiene que usar el telefono;
# el nombre de host NO se configura: se toma de la cabecera Host de la peticion,
# asi la misma imagen sirve en cualquier instancia sin tocar variables.
GUAC_INTERNA = os.environ.get("AR_GUAC_INTERNA", "http://127.0.0.1:8080/guacamole")
GUAC_PUERTO_PUBLICO = os.environ.get("AR_GUAC_PUERTO_PUBLICO", "8080")
GUAC_URL_PUBLICA = os.environ.get("AR_GUAC_URL_PUBLICA", "")
GUAC_USUARIO = os.environ.get("AR_GUAC_USUARIO", "supervisor")
GUAC_PASSWORD = os.environ.get("AR_GUAC_PASSWORD", "")
PROXY_CONTENEDOR = os.environ.get("AR_PROXY_CONTENEDOR", "nginx_proxy")

# Umbrales. Por encima de "atencion" el estado global deja de ser Operativo.
UMBRAL = {"cpu_warn": 80, "cpu_crit": 92, "ram_warn": 80, "ram_crit": 92,
          "disco_warn": 80, "disco_crit": 92}


# ---------------------------------------------------------------- utilidades

def sh(cmd, timeout=8):
    """Ejecuta un comando y devuelve stdout, o cadena vacia si falla."""
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True,
                           text=True, timeout=timeout)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def sql(consulta, timeout=12):
    """
    Lanza una consulta contra MariaDB y devuelve las filas ya troceadas.

    La consulta va por STDIN, no incrustada en la linea de comandos.

    No es un capricho: metiendola en el comando hay que anidar tres niveles de
    comillas (Python -> sh -c '...' -> mariadb -e "..."), y una comilla simple
    dentro del SQL cierra el sh -c antes de tiempo. El comando falla, sh()
    devuelve cadena vacia y la API reporta cero sesiones sin dar ningun error:
    justo el tipo de fallo silencioso que no se ve hasta que alguien nota que
    los numeros no cuadran con el panel de Guacamole. Paso por aqui.

    Con stdin el SQL viaja como datos, no como texto que otro shell reinterpreta.
    """
    cmd = ["docker", "exec", "-i", "guacamole_db", "sh", "-c",
           'exec mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B ' + BASE_GUAC]
    try:
        r = subprocess.run(cmd, input=consulta, capture_output=True,
                           text=True, timeout=timeout)
        if r.returncode != 0:
            return []
        return [l.split("\t") for l in r.stdout.strip().splitlines() if l.strip()]
    except Exception:
        return []


def puerto_escucha(puerto, host="127.0.0.1"):
    with socket.socket() as s:
        s.settimeout(1.0)
        return s.connect_ex((host, puerto)) == 0


# ---------------------------------------------------------------- metricas

_cpu_previo = {"total": 0, "ocioso": 0}


def cpu_por_ciento():
    """
    Uso de CPU a partir de /proc/stat.

    Se calcula como delta entre llamadas, que es la unica forma correcta:
    /proc/stat da contadores acumulados desde el arranque, no un porcentaje.
    La primera llamada tras iniciar el servicio devuelve el promedio desde
    el arranque; a partir de la segunda, el uso real del intervalo.
    """
    try:
        with open("/proc/stat") as f:
            campos = [int(x) for x in f.readline().split()[1:]]
    except Exception:
        return 0.0

    total = sum(campos)
    ocioso = campos[3] + (campos[4] if len(campos) > 4 else 0)  # idle + iowait

    dt = total - _cpu_previo["total"]
    di = ocioso - _cpu_previo["ocioso"]
    _cpu_previo["total"], _cpu_previo["ocioso"] = total, ocioso

    if dt <= 0:
        return 0.0
    return round(100.0 * (dt - di) / dt, 1)


def memoria():
    datos = {}
    try:
        with open("/proc/meminfo") as f:
            for linea in f:
                k, _, v = linea.partition(":")
                datos[k] = int(v.split()[0])  # kB
    except Exception:
        return {}

    total = datos.get("MemTotal", 0)
    disp = datos.get("MemAvailable", 0)
    usada = total - disp
    swap_total = datos.get("SwapTotal", 0)
    swap_libre = datos.get("SwapFree", 0)

    return {
        "total_mb": round(total / 1024),
        "usada_mb": round(usada / 1024),
        "disponible_mb": round(disp / 1024),
        "por_ciento": round(100.0 * usada / total, 1) if total else 0.0,
        "swap_total_mb": round(swap_total / 1024),
        "swap_usada_mb": round((swap_total - swap_libre) / 1024),
    }


def disco():
    try:
        u = shutil.disk_usage("/")
        return {"total_gb": round(u.total / 1024**3, 1),
                "usado_gb": round(u.used / 1024**3, 1),
                "por_ciento": round(100.0 * u.used / u.total, 1)}
    except Exception:
        return {}


def red():
    """Trafico acumulado de todas las interfaces salvo loopback."""
    rx = tx = 0
    try:
        with open("/proc/net/dev") as f:
            for linea in f.readlines()[2:]:
                nombre, _, resto = linea.partition(":")
                if nombre.strip() == "lo":
                    continue
                c = resto.split()
                rx += int(c[0])
                tx += int(c[8])
    except Exception:
        pass
    return {"entrada_mb": round(rx / 1024**2, 1), "salida_mb": round(tx / 1024**2, 1)}


def arranque():
    try:
        with open("/proc/uptime") as f:
            seg = float(f.readline().split()[0])
        return {"segundos": int(seg), "texto": formato_duracion(seg)}
    except Exception:
        return {"segundos": 0, "texto": "?"}


def desde_hace(fecha):
    """
    Convierte "2026-08-12 23:04:34" en "hace 12 min".

    MariaDB guarda las fechas del historial en UTC, igual que el reloj de la
    instancia, asi que se comparan en UTC y no hay que adivinar zona horaria.
    """
    if not fecha or fecha in ("NULL", ""):
        return None
    try:
        t = time.mktime(time.strptime(fecha, "%Y-%m-%d %H:%M:%S"))
        # strptime interpreta en local; el reloj de la instancia esta en UTC,
        # asi que se compara contra la misma referencia.
        delta = time.mktime(time.gmtime()) - t
        if delta < 0:
            delta = 0
        return "hace " + formato_duracion(delta) if delta >= 60 else "hace un momento"
    except Exception:
        return None


def formato_duracion(seg):
    seg = int(seg)
    d, seg = divmod(seg, 86400)
    h, seg = divmod(seg, 3600)
    m = seg // 60
    if d:
        return "%d d %02d h" % (d, h)
    if h:
        return "%d h %02d min" % (h, m)
    return "%d min" % m


# ---------------------------------------------------------------- servicios

CONTENEDORES = [
    ("Entrada web", PROXY_CONTENEDOR, "Recibe las visitas de internet y pone el candado de seguridad.", "443"),
    ("Portal", "guacamole_web", "La pagina donde el alumno entra y ve su escritorio.", "8080"),
    ("Traductor", "guacd", "Convierte la pantalla del servidor para que se vea en el navegador.", "4822"),
    ("Base de datos", "guacamole_db", "Guarda los usuarios, sus permisos y el registro de conexiones.", "3306"),
]


def estado_contenedor(nombre):
    # OJO con la plantilla: .State.Health solo existe si la imagen declara un
    # HEALTHCHECK. Referenciarla directamente hace que "docker inspect" falle
    # entero en los contenedores que no lo tienen, y el servicio se reporta
    # como "No existe" aunque este corriendo perfectamente. De los cuatro
    # contenedores solo guacd trae healthcheck, asi que sin el "{{if}}" los
    # otros tres salian caidos siempre.
    plantilla = ("{{.State.Status}}|"
                 "{{if .State.Health}}{{.State.Health.Status}}{{end}}|"
                 "{{.State.StartedAt}}")
    salida = sh('docker inspect -f "%s" %s' % (plantilla, nombre))
    if not salida:
        return "crit", "No existe", ""
    partes = salida.split("|")
    estado = partes[0]
    salud = partes[1] if len(partes) > 1 else ""
    desde = partes[2] if len(partes) > 2 else ""

    if estado != "running":
        return "crit", "Detenido", desde
    # "starting" es transitorio: el contenedor arranco pero aun no pasa su
    # propio healthcheck. No es un fallo, es que todavia no termina.
    if salud in ("starting",):
        return "warn", "Arrancando", desde
    if salud == "unhealthy":
        return "warn", "Con problemas", desde
    return "ok", "Operativo", desde


def servicios():
    lista = [{
        "nombre": "Servidor",
        "clave": "ec2",
        "descripcion": "La maquina en la nube donde vive todo el laboratorio.",
        "estado": "ok",
        "estado_texto": "Operativo",
        "puerto": obtener_ip_privada(),
        "uptime": arranque()["texto"],
        "evento": "Encendido desde hace %s." % arranque()["texto"],
    }]

    for etiqueta, contenedor, desc, puerto in CONTENEDORES:
        estado, texto, desde = estado_contenedor(contenedor)
        lista.append({
            "nombre": etiqueta,
            "clave": contenedor,
            "descripcion": desc,
            "estado": estado,
            "estado_texto": texto,
            "puerto": puerto,
            "uptime": desde[:19].replace("T", " ") if desde else "",
            "evento": "Contenedor %s: %s." % (contenedor, texto.lower()),
        })

    # Escritorios: una unit de systemd por usuario
    unidades = sh("systemctl list-units 'vncserver-*.service' --no-legend --plain") or ""
    activos = len([l for l in unidades.splitlines() if " active " in l or "\tactive\t" in l or " running" in l])
    total_unidades = len([l for l in unidades.splitlines() if l.strip()])
    puertos = [p for p in range(5901, 5910) if puerto_escucha(p, obtener_ip_privada() or "127.0.0.1")]

    if total_unidades == 0:
        est, txt = "crit", "Sin configurar"
    elif len(puertos) == 0:
        est, txt = "crit", "Detenido"
    elif len(puertos) < total_unidades:
        est, txt = "warn", "Revisando"
    else:
        est, txt = "ok", "Operativo"

    lista.append({
        "nombre": "Escritorios",
        "clave": "vnc",
        "descripcion": "Los escritorios Linux, uno por persona.",
        "estado": est,
        "estado_texto": txt,
        "puerto": "-".join([str(puertos[0]), str(puertos[-1])]) if puertos else "ninguno",
        "uptime": "",
        "evento": "%d de %d escritorios escuchando." % (len(puertos), max(total_unidades, len(puertos))),
    })
    return lista


_ip_privada = None


def obtener_ip_privada():
    """
    IP privada de la instancia dentro de la VPC.

    Se obtiene abriendo un socket UDP hacia una direccion externa y leyendo la
    IP local que el kernel elige para esa ruta. No envia ni un solo paquete
    (UDP no establece conexion) y no depende de "hostname -I", que bajo
    systemd con ProtectSystem no siempre resuelve igual y devolvia 127.0.0.1.
    """
    global _ip_privada
    if _ip_privada is None:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.settimeout(1.0)
                s.connect(("10.255.255.255", 1))
                _ip_privada = s.getsockname()[0]
        except Exception:
            _ip_privada = sh("hostname -I | cut -d' ' -f1") or "127.0.0.1"
    return _ip_privada


# ---------------------------------------------------------------- sesiones

def sesiones():
    """
    Conexiones definidas en Guacamole y cuales estan en uso.

    La actividad sale de guacamole_connection_history: una fila con end_date
    NULL es una sesion abierta ahora mismo. Es la misma fuente que usa el
    panel de Guacamole, asi que los numeros coinciden con lo que ve el
    administrador en la web.
    """
    consulta = """
SELECT c.connection_name,
       MAX(CASE WHEN p.parameter_name = 'port' THEN p.parameter_value END),
       c.connection_id,
       (SELECT COUNT(*) FROM guacamole_connection_history h
         WHERE h.connection_id = c.connection_id AND h.end_date IS NULL),
       (SELECT MIN(h2.start_date) FROM guacamole_connection_history h2
         WHERE h2.connection_id = c.connection_id AND h2.end_date IS NULL),
       (SELECT GROUP_CONCAT(DISTINCT h3.username) FROM guacamole_connection_history h3
         WHERE h3.connection_id = c.connection_id AND h3.end_date IS NULL)
FROM guacamole_connection c
LEFT JOIN guacamole_connection_parameter p ON p.connection_id = c.connection_id
GROUP BY c.connection_id
ORDER BY c.connection_name;
"""
    filas = sql(consulta)

    items = []
    for campos in filas:
        if len(campos) < 4:
            continue
        nombre, puerto, cid, abiertas = campos[0], campos[1], campos[2], campos[3]
        desde = campos[4] if len(campos) > 4 else "NULL"
        quien = campos[5] if len(campos) > 5 else "NULL"
        activa = abiertas not in ("0", "NULL", "")
        escuchando = puerto_escucha(int(puerto), obtener_ip_privada()) if puerto.isdigit() else False
        items.append({
            "conexion": nombre,
            "id": cid,
            "puerto": puerto,
            "activa": activa,
            "usuario": None if quien in ("NULL", "") else quien,
            "escritorio_listo": escuchando,
            "desde": None if desde in ("NULL", "") else desde,
            "desde_texto": desde_hace(desde),
            "estado_texto": "En uso" if activa else ("Libre" if escuchando else "Escritorio caido"),
            "estado": "live" if activa else ("mute" if escuchando else "crit"),
        })

    return {"limite": LIMITE_SESIONES,
            "activas": sum(1 for i in items if i["activa"]),
            "conexiones": items}


# ------------------------------------------------------- escritorio remoto

# La sesion de Guacamole se reutiliza mientras siga viva. Pedir una nueva en
# cada toque llenaria guacamole_user_history de entradas de "supervisor" y
# ensuciaria la auditoria de quien entro a que.
_guac = {"token": None, "fuente": None, "caduca": 0}
_guac_lock = threading.Lock()

# Guacamole invalida el token tras una hora de inactividad. Se renueva a los 45
# minutos para no llegar nunca al borde con una sesion abierta a medias.
GUAC_VIDA_SEG = 45 * 60


def _guac_pedir_token():
    """
    Autentica contra la API REST de Guacamole y devuelve (token, fuente_datos).

    "fuente_datos" es el identificador del backend de autenticacion (aqui
    "mysql"). Hace falta para construir el identificador de cliente: Guacamole
    admite varios backends a la vez y el id de conexion solo es unico dentro
    de uno.
    """
    datos = urllib.parse.urlencode({
        "username": GUAC_USUARIO,
        "password": GUAC_PASSWORD,
    }).encode("utf-8")

    peticion = urllib.request.Request(
        GUAC_INTERNA.rstrip("/") + "/api/tokens",
        data=datos,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with urllib.request.urlopen(peticion, timeout=10) as r:
        cuerpo = json.loads(r.read().decode("utf-8"))
    return cuerpo["authToken"], cuerpo.get("dataSource", "mysql")


def guac_sesion():
    """Token de Guacamole vigente, pidiendo uno nuevo solo si hace falta."""
    with _guac_lock:
        if _guac["token"] and time.time() < _guac["caduca"]:
            return _guac["token"], _guac["fuente"]
        token, fuente = _guac_pedir_token()
        _guac.update({"token": token, "fuente": fuente,
                      "caduca": time.time() + GUAC_VIDA_SEG})
        return token, fuente


def guac_invalidar():
    with _guac_lock:
        _guac.update({"token": None, "fuente": None, "caduca": 0})


def identificador_cliente(id_conexion, fuente):
    """
    Identificador que Guacamole espera en /#/client/<esto>.

    Es base64 de tres campos separados por bytes nulos: id de la conexion, el
    tipo ("c" de connection, frente a "g" de grupo) y la fuente de datos.
    Se documenta aqui porque no hay forma de deducirlo leyendo la URL: en el
    navegador solo se ve la cadena ya codificada.
    """
    crudo = ("%s\0c\0%s" % (id_conexion, fuente)).encode("utf-8")
    return base64.b64encode(crudo).decode("ascii")


def escritorio(nombre_conexion, host_peticion):
    """
    Devuelve la URL lista para abrir el escritorio de esa conexion.

    El host se toma de la cabecera Host de la peticion: el telefono ya sabe por
    que direccion alcanza la instancia, asi que no hay que configurarla dos
    veces ni adivinar la IP publica desde dentro de la VPC (donde no se ve).
    """
    if not GUAC_PASSWORD:
        return None, ("Guacamole no esta configurado en la API",
                      "Falta AR_GUAC_PASSWORD. Relanza el rol api de Ansible.")

    filas = sql("SELECT connection_id FROM guacamole_connection "
                "WHERE connection_name = '%s';" % nombre_conexion.replace("'", ""))
    if not filas:
        return None, ("Esa conexion no existe en Guacamole",
                      "Revisa el nombre en la pestana Sesiones.")
    id_conexion = filas[0][0]

    try:
        token, fuente = guac_sesion()
    except urllib.error.HTTPError as e:
        guac_invalidar()
        if e.code == 403:
            return None, ("Guacamole rechazo al usuario supervisor",
                          "La contrasena de la API y la de Guacamole no coinciden. "
                          "Relanza el rol api de Ansible.")
        return None, ("Guacamole respondio %d" % e.code, "Revisa el contenedor guacamole_web.")
    except Exception as e:
        guac_invalidar()
        return None, ("No se pudo hablar con Guacamole", str(e)[:120])

    # host_peticion llega como "1.2.3.4:8000". Se le quita el puerto de la API
    # y se le pone el del portal.
    solo_host = host_peticion.split(":")[0] if host_peticion else obtener_ip_privada()
    base = (GUAC_URL_PUBLICA.rstrip("/") if GUAC_URL_PUBLICA else
            "http://%s:%s/guacamole" % (solo_host, GUAC_PUERTO_PUBLICO))

    cliente = identificador_cliente(id_conexion, fuente)
    return {
        "conexion": nombre_conexion,
        "id": id_conexion,
        "url": "%s/#/client/%s?token=%s" % (base, cliente, urllib.parse.quote(token)),
        "portal": base,
        "vence_en": GUAC_VIDA_SEG,
    }, None


# ---------------------------------------------------------------- alertas

def alertas(res, svc, ses):
    out = []

    ram = res["memoria"].get("por_ciento", 0)
    if ram >= UMBRAL["ram_crit"]:
        out.append(("alta", "crit", "La memoria llego al %s%%" % ram,
                    "Cierra escritorios que no se esten usando. Por encima de este punto el sistema empieza a matar procesos."))
    elif ram >= UMBRAL["ram_warn"]:
        out.append(("alta", "warn", "La memoria llego al %s%%" % ram,
                    "Revisa si hay escritorios que puedas cerrar antes de que entren mas personas."))

    cpu = res["cpu"]["por_ciento"]
    if cpu >= UMBRAL["cpu_crit"]:
        out.append(("alta", "crit", "El procesador esta al %s%%" % cpu,
                    "Todo va a ir lento. Suele ser una topologia de GNS3 muy grande."))
    elif cpu >= UMBRAL["cpu_warn"]:
        out.append(("media", "warn", "El procesador esta al %s%%" % cpu,
                    "Vigila si se mantiene asi varios minutos."))

    d = res["disco"].get("por_ciento", 0)
    if d >= UMBRAL["disco_warn"]:
        out.append(("alta" if d >= UMBRAL["disco_crit"] else "media",
                    "crit" if d >= UMBRAL["disco_crit"] else "warn",
                    "El disco esta al %s%%" % d,
                    "Si se llena, MariaDB deja de escribir y nadie puede entrar."))

    for s in svc:
        if s["estado"] == "crit":
            out.append(("alta", "crit", "%s: %s" % (s["nombre"], s["estado_texto"].lower()),
                        "Sin este servicio el laboratorio no funciona. Avisa al equipo tecnico."))
        elif s["estado"] == "warn":
            out.append(("media", "warn", "%s: %s" % (s["nombre"], s["estado_texto"].lower()),
                        "Vuelve a revisar en unos minutos; puede normalizarse solo."))

    libres = ses["limite"] - ses["activas"]
    if libres <= 0:
        out.append(("alta", "warn", "No quedan escritorios libres",
                    "Los siguientes alumnos tendran que esperar a que alguien salga."))
    elif libres == 1:
        out.append(("baja", "mute", "Queda 1 escritorio libre",
                    "Sin accion necesaria. Solo para que lo tengas presente."))

    if not out:
        out.append(("baja", "ok", "Todo funciona bien", "No hay nada pendiente por revisar."))

    return [{"nivel": n, "tono": t, "que": q, "consejo": c} for n, t, q, c in out]


# ---------------------------------------------------------------- estado global

def recursos():
    return {"cpu": {"por_ciento": cpu_por_ciento()},
            "memoria": memoria(), "disco": disco(), "red": red(), "arranque": arranque()}


def estado_completo():
    res = recursos()
    svc = servicios()
    ses = sesiones()
    ale = alertas(res, svc, ses)

    if any(s["estado"] == "crit" for s in svc) or any(a["tono"] == "crit" for a in ale):
        global_estado, palabra = "crit", "Critico"
    elif any(s["estado"] == "warn" for s in svc) or any(a["tono"] == "warn" for a in ale):
        global_estado, palabra = "warn", "Atencion"
    else:
        global_estado, palabra = "ok", "Operativo"

    if global_estado == "ok":
        mensaje = "Todo funciona bien. No hay nada pendiente por revisar."
    else:
        mensaje = ale[0]["que"] + ". " + ale[0]["consejo"]

    return {
        "generado": int(time.time()),
        "estado": global_estado,
        "estado_texto": palabra,
        "mensaje": mensaje,
        "recursos": res,
        "servicios": svc,
        "sesiones": ses,
        "alertas": ale,
    }


# ---------------------------------------------------------------- HTTP

class Handler(BaseHTTPRequestHandler):
    server_version = "AulaRemotaAPI/1.0"

    def log_message(self, fmt, *args):
        pass  # sin log de acceso: no aporta y llena el journal

    def _json(self, codigo, cuerpo):
        datos = json.dumps(cuerpo, ensure_ascii=False).encode("utf-8")
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(datos)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(datos)

    def _autorizado(self):
        if not TOKEN:
            return False
        cabecera = self.headers.get("Authorization", "")
        if not cabecera.startswith("Bearer "):
            return False
        return hmac.compare_digest(cabecera[7:], TOKEN)

    def do_GET(self):
        partido = urllib.parse.urlparse(self.path)
        ruta = partido.path.rstrip("/") or "/"
        consulta = urllib.parse.parse_qs(partido.query)

        if ruta in ("/salud", "/api/v1/salud"):
            return self._json(200, {"ok": True, "servicio": "aula-remota-api"})

        if not self._autorizado():
            return self._json(401, {"error": "Token invalido o ausente"})

        try:
            if ruta in ("/api/v1/estado", "/"):
                return self._json(200, estado_completo())
            if ruta == "/api/v1/recursos":
                return self._json(200, recursos())
            if ruta == "/api/v1/servicios":
                return self._json(200, {"servicios": servicios()})
            if ruta == "/api/v1/sesiones":
                return self._json(200, sesiones())
            if ruta == "/api/v1/alertas":
                r, s, x = recursos(), servicios(), sesiones()
                return self._json(200, {"alertas": alertas(r, s, x)})
            if ruta == "/api/v1/escritorio":
                nombre = (consulta.get("conexion") or [""])[0]
                if not nombre:
                    return self._json(400, {"error": "Falta el parametro conexion"})
                datos, fallo = escritorio(nombre, self.headers.get("Host", ""))
                if fallo:
                    return self._json(502, {"error": fallo[0], "detalle": fallo[1]})
                return self._json(200, datos)
        except Exception as e:
            return self._json(500, {"error": "Fallo al recoger datos", "detalle": str(e)[:200]})

        self._json(404, {"error": "Ruta no encontrada"})


def main():
    if not TOKEN:
        raise SystemExit("AR_API_TOKEN vacio: el servicio no arranca sin token.")
    cpu_por_ciento()  # primera lectura, para que la siguiente tenga delta
    servidor = ThreadingHTTPServer((HOST, PORT), Handler)
    servidor.daemon_threads = True
    print("API de Aula Remota escuchando en %s:%d" % (HOST, PORT), flush=True)
    servidor.serve_forever()


if __name__ == "__main__":
    main()
