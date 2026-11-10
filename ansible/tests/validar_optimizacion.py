#!/usr/bin/env python3
"""Valida las decisiones criticas de la optimizacion sin tocar un host."""

import ast
import re
from datetime import datetime, timezone
from pathlib import Path

import jinja2
import yaml

ROOT = Path(__file__).resolve().parents[1]


def cargar_yaml(path):
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def entorno_templates(role):
    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(str(ROOT / "roles" / role / "templates")),
        undefined=jinja2.StrictUndefined,
        keep_trailing_newline=True,
    )
    env.filters["bool"] = bool
    env.filters["regex_findall"] = lambda texto, patron: re.findall(patron, texto)
    return env


def render_compose(proxy):
    valores = {
        **cargar_yaml(ROOT / "inventory/group_vars/lab/main.yml"),
        **cargar_yaml(ROOT / "roles/docker_stack/defaults/main.yml"),
        **cargar_yaml(ROOT / "roles/tuning_host/defaults/main.yml"),
        "mysql_root_password": "SOLO_PRUEBA",
        "mysql_user_password": "SOLO_PRUEBA",
        "proxy_activo": proxy,
    }
    texto = (
        entorno_templates("docker_stack")
        .get_template("docker-compose.yml.j2")
        .render(**valores)
    )
    return yaml.safe_load(texto)


def validar_compose():
    for proxy in ("npm", "caddy"):
        compose = render_compose(proxy)
        servicios = compose["services"]
        activo = servicios[proxy]
        inactivo = servicios["caddy" if proxy == "npm" else "npm"]

        assert {"80:80", "443:443"}.issubset(set(activo.get("ports", [])))
        assert not inactivo.get("ports")
        assert servicios["guacamole"]["mem_limit"] == "384m"
        assert (
            "mem_limit" not in servicios["db"]
        ), "MariaDB no debe tener un limite duro sin medir"
        valve = servicios["guacamole"]["environment"].get("REMOTE_IP_VALVE_ENABLED")
        assert valve == ("true" if proxy == "caddy" else None)

        for servicio in servicios.values():
            assert servicio["logging"]["options"] == {
                "max-size": "10m",
                "max-file": "3",
            }

        guac_ports = servicios["guacamole"]["ports"]
        if proxy == "caddy":
            assert guac_ports == ["127.0.0.1:8080:8080"]
        else:
            assert guac_ports == ["8080:8080"]


def tarea(role, nombre):
    def recorrer(tareas):
        for t in tareas:
            yield t
            for bloque in ("block", "rescue", "always"):
                yield from recorrer(t.get(bloque, []))

    return next(
        t
        for t in recorrer(cargar_yaml(ROOT / "roles" / role / "tasks/main.yml"))
        if t["name"] == nombre
    )


def condiciones(env, expresiones, valores):
    if isinstance(expresiones, str):
        expresiones = [expresiones]
    return all(env.compile_expression(e)(**valores) for e in expresiones)


def validar_zswap():
    env = entorno_templates("tuning_host")
    valores = {
        **cargar_yaml(ROOT / "roles/tuning_host/defaults/main.yml"),
        "ansible_check_mode": False,
        "zswap_sysfs": {"stat": {"exists": True}},
        "tuning_host_zswap_actual": {
            "results": [{"stdout": v} for v in ("N\n", "20\n", "lzo\n", "zbud\n")]
        },
        "tuning_host_zswap_crypto": {
            "stdout": "name         : lzo\nname         : lz4\n"
        },
    }
    facts = tarea("tuning_host", "Guardar los valores actuales de zswap")[
        "ansible.builtin.set_fact"
    ]
    for nombre, expresion in facts.items():
        valores[nombre] = env.from_string(expresion).render(**valores)
    # Leer lzo/zbud de sysfs no impide seleccionar lz4/z3fold.
    assert valores["tuning_host_zswap_compressor_actual"] == "lzo"
    assert valores["tuning_host_zswap_zpool_actual"] == "zbud"
    # El filtro devuelve una lista nativa en Ansible; evaluamos su expresion aqui.
    expr = facts["tuning_host_zswap_compresores_registrados"].strip()[2:-2]
    valores["tuning_host_zswap_compresores_registrados"] = env.compile_expression(expr)(
        **valores
    )
    compresor = tarea("tuning_host", "Configurar el compresor de zswap en caliente")
    allocator = tarea("tuning_host", "Configurar el allocator de zswap en caliente")
    assert condiciones(env, compresor["when"], valores)
    assert condiciones(env, allocator["when"], valores)
    valores["tuning_host_zswap_compressor_actual"] = "lz4"
    valores["tuning_host_zswap_zpool_actual"] = "z3fold"
    assert not condiciones(env, compresor["when"], valores)
    assert not condiciones(env, allocator["when"], valores)
    valores["tuning_host_zswap_compressor_actual"] = "lzo"
    valores["tuning_host_zswap_compresores_registrados"] = ["lzo", "lz4hc"]
    assert not condiciones(env, compresor["when"], valores)

    validacion = tarea("tuning_host", "Comprobar zswap efectivo antes de persistir")
    resultados = {
        "enabled": "Y",
        "max_pool_percent": "20",
        "compressor": "lz4",
        "zpool": "z3fold",
    }
    valores["tuning_host_zswap_efectivo"] = resultados
    assert condiciones(env, validacion["ansible.builtin.assert"]["that"], valores)
    valores["tuning_host_zswap_efectivo"] = dict(resultados, zpool="zbud")
    assert not condiciones(env, validacion["ansible.builtin.assert"]["that"], valores)

    aviso = tarea("tuning_host", "Advertir si la prueba runtime de zswap no es valida")
    assert "ansible.builtin.debug" in aviso
    for efectivo in (
        dict(resultados, enabled="N"),
        dict(resultados, max_pool_percent="10"),
    ):
        valores["tuning_host_zswap_efectivo"] = efectivo
        assert condiciones(env, aviso["when"], valores)
        assert not condiciones(
            env, validacion["ansible.builtin.assert"]["that"], valores
        )
    valores["tuning_host_zswap_efectivo"] = resultados
    assert not condiciones(env, aviso["when"], valores)
    prueba = tarea("tuning_host", "Probar zswap sin interrumpir el despliegue")
    assert prueba[
        "rescue"
    ], "Los errores de sysfs tampoco deben bloquear la prueba opcional"
    assert validacion in cargar_yaml(ROOT / "roles/tuning_host/tasks/main.yml"), (
        "La comprobacion de persistencia debe quedar fuera del rescue runtime"
    )


def validar_proxy_y_respaldo():
    roles = cargar_yaml(ROOT / "site.yml")[0]["roles"]
    assert {"docker", "caddy"}.issubset(
        next(r["tags"] for r in roles if r["role"] == "caddy")
    )
    env = entorno_templates("caddy")
    env.globals["now"] = lambda **_: datetime.fromtimestamp(1000000, timezone.utc)
    validacion = tarea("caddy", "Exigir un respaldo reciente de NPM antes de migrar")
    valores = {"caddy_npm_backup_max_age_seconds": 86400}
    predicados = validacion["ansible.builtin.assert"]["that"]
    for datos, esperado in [
        ({"exists": False}, False),
        ({"exists": True, "isreg": True, "size": 0, "mtime": 999900}, False),
        ({"exists": True, "isreg": True, "size": 100, "mtime": 900000}, False),
        ({"exists": True, "isreg": True, "size": 100, "mtime": 1000100}, False),
        ({"exists": True, "isreg": False, "size": 100, "mtime": 999900}, False),
        ({"exists": True, "isreg": True, "size": 100, "mtime": 999900}, True),
    ]:
        valores["caddy_npm_respaldo"] = {"stat": datos}
        assert condiciones(env, predicados, valores) == esperado

    decision = tarea("caddy", "Determinar si hay una transicion de proxy")[
        "ansible.builtin.set_fact"
    ]
    detener = tarea("caddy", "Detener el proxy inactivo")
    for (
        proxy,
        existe_caddy,
        corriendo_caddy,
        existe_npm,
        requiere,
        detener_inactivo,
    ) in [
        ("npm", False, False, False, False, False),
        ("npm", True, True, True, False, True),
        ("caddy", False, False, True, True, True),
        ("caddy", True, False, True, True, True),
        ("caddy", True, True, True, False, True),
        ("caddy", True, True, False, False, False),
    ]:
        estado = {
            "proxy_activo": proxy,
            "caddy_contenedores_previos": {
                "results": [
                    {
                        "exists": existe_caddy,
                        "container": (
                            {"State": {"Running": corriendo_caddy}}
                            if existe_caddy
                            else None
                        ),
                    },
                    {"exists": existe_npm},
                ]
            },
        }
        for nombre, expr in decision.items():
            estado[nombre] = env.compile_expression(expr.strip()[2:-2])(**estado)
        assert condiciones(env, validacion["when"], estado) == requiere
        assert condiciones(env, detener["when"], estado) == detener_inactivo
        consulta = tarea("caddy", "Consultar el respaldo de NPM en el nodo de control")
        assert condiciones(env, consulta["when"], estado) == requiere
    validacion_config = tarea("caddy", "Validar el Caddyfile antes del cambio de proxy")
    assert not condiciones(env, validacion_config["when"], {"proxy_activo": "npm"})
    assert condiciones(env, validacion_config["when"], {"proxy_activo": "caddy"})
    assert (
        "caddy validate --config" in validacion_config["ansible.builtin.command"]["cmd"]
    )
    tareas_proxy = cargar_yaml(ROOT / "roles/caddy/tasks/main.yml")
    assert tareas_proxy.index(validacion) < next(
        i for i, t in enumerate(tareas_proxy) if "ansible.builtin.file" in t
    )
    respaldo = cargar_yaml(ROOT / "playbooks/backup-npm.yml")[0]["tasks"]
    reinicio = next(t for t in respaldo if t["name"] == "Volver a levantar NPM")
    assert reinicio["community.docker.docker_compose_v2"]["services"] == ["npm"]
    assert reinicio["community.docker.docker_compose_v2"]["profiles"] == ["npm"]


def validar_mensajes():
    env = entorno_templates("docker_stack")
    mensajes = cargar_yaml(ROOT / "roles/docker_stack/tasks/main.yml")
    for proxy, staging in [("npm", True), ("caddy", True), ("caddy", False)]:
        valores = {
            **cargar_yaml(ROOT / "inventory/group_vars/lab/main.yml"),
            "proxy_activo": proxy,
            "caddy_acme_staging": staging,
        }
        salida = []
        for t in mensajes:
            if t["name"].startswith("Mostrar el acceso al portal") and condiciones(
                env, t["when"], valores
            ):
                salida.extend(
                    env.from_string(m).render(**valores)
                    for m in t["ansible.builtin.debug"]["msg"]
                )
        texto = "\n".join(salida)
        if proxy == "caddy":
            assert "https://" + valores["lab_fqdn"] + "/guacamole" in texto
            assert ("STAGING" in texto) == staging
            assert "Nginx Proxy Manager" not in texto
        else:
            assert "puerto 81" in texto


def validar_plantillas():
    sql = (ROOT / "roles/docker_stack/templates/02-conexiones.sql.j2").read_text(
        encoding="utf-8"
    )
    assert "'color-depth', '16'" in sql

    unit = (ROOT / "roles/vnc/templates/vncserver.service.j2").read_text(
        encoding="utf-8"
    )
    assert "MemoryHigh={{ vnc_memory_high }}" in unit
    assert "CPUQuota={{ vnc_cpu_quota }}" in unit
    assert "TasksMax={{ vnc_tasks_max }}" in unit
    assert "MemoryMax=" not in unit

    valores = {
        **cargar_yaml(ROOT / "inventory/group_vars/lab/main.yml"),
        **cargar_yaml(ROOT / "roles/caddy/defaults/main.yml"),
    }
    caddyfile = (
        entorno_templates("caddy").get_template("Caddyfile.j2").render(**valores)
    )
    assert valores["caddy_staging_ca"] in caddyfile
    assert "reverse_proxy guacamole_web:8080" in caddyfile


def validar_python():
    api = (ROOT / "roles/api/files/api.py").read_text(encoding="utf-8")
    ast.parse(api)
    assert 'os.environ.get("AR_PROXY_CONTENEDOR"' in api
    assert 'os.environ.get("AR_GUAC_URL_PUBLICA"' in api


if __name__ == "__main__":
    validar_compose()
    validar_plantillas()
    validar_python()
    validar_zswap()
    validar_proxy_y_respaldo()
    validar_mensajes()
    print("OK: Compose NPM/Caddy, zswap opcional, transicion y respaldo de NPM")
