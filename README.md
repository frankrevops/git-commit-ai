# gato.sh

**Generador minimalista de mensajes de commit usando Qwen CLI local.**

Hecho por **Frank I. (frankrevops)**.

Este script está diseñado para desarrolladores que buscan mensajes de commit precisos, técnicos y con bajo nivel de prosa. Se enfoca en generar un asunto conciso y un cuerpo con viñetas basado en los cambios del repositorio.

## Requisitos

Para utilizar `gato.sh`, necesitas tener instaladas las siguientes herramientas en tu sistema:

1.  **git**: El sistema de control de versiones.
2.  **qwen CLI**: La interfaz de línea de comandos para el modelo Qwen. Asegúrate de que el comando `qwen` esté disponible en tu `PATH`.

## Instalación

Simplemente descarga el script `gato.sh` y dale permisos de ejecución:

```bash
chmod +x gato.sh
```

## Uso

Ejecuta el script dentro de un repositorio git.

```bash
./gato.sh [opciones]
```

### Opciones

| Comando | Descripción |
| :--- | :--- |
| `./gato.sh` | **Vista previa**: Genera un mensaje basado en los cambios preparados (staged) o no preparados (unstaged) sin realizar el commit. |
| `./gato.sh -local` | **Local**: Prepara todos los cambios (`git add -A`), genera el mensaje y realiza el commit. |
| `./gato.sh -push` | **Push**: Prepara todo, hace commit y empuja los cambios al remoto (`git push`). |
| `./gato.sh -test` | **Test**: Simula la generación de un mensaje con datos de prueba (no lee datos reales de git). |
| `./gato.sh -y` | Salta las confirmaciones interactivas (útil para scripts). |
| `./gato.sh --analyze` | Muestra solo el contexto del análisis que se enviaría a la IA. |
| `./gato.sh -h` | Muestra la ayuda. |

### Variables de Entorno

Puedes configurar el comportamiento usando variables de entorno:

*   `GITGPT_MAX_PATCH_LINES`: Número máximo de líneas del patch a enviar a qwen (por defecto: 2500).
*   `GITGPT_RETRIES`: Número de reintentos si la salida de qwen es inválida o vacía (por defecto: 2).
*   `GITGPT_MODEL`: Sugerencia opcional del modelo a incluir en el prompt.

## Ejemplo

```bash
$ ./gato.sh
Analyzing staged changes...

═══════════════════════════════════════════════════════
Suggested commit:
═══════════════════════════════════════════════════════
refactor: update authentication logic

- simplify token validation in auth.middleware.ts
- remove redundant user check in login controller
- update tests to reflect new error messages
═══════════════════════════════════════════════════════

Commit with this message? [Y/n]
```
