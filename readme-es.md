# iCUE Watchdog

> Corrige automáticamente el fallo de comunicación interna (IPC) de iCUE 5 que hace que
> los dispositivos Corsair dejen de ser detectados tras despertar el PC, reanudar desde
> hibernación o desbloquear la sesión de Windows. Cuando ocurre, iCUE pierde el control
> sobre **iluminación RGB, perfiles de ventiladores y RAM** de todos los dispositivos
> gestionados.

---

## El problema

Si tienes periféricos Corsair con iCUE 5, es muy probable que te hayas encontrado con
esto: enciendes el monitor, desbloqueas Windows, y de repente el teclado ya no tiene
iluminación, el ratón tampoco, y al abrir iCUE la lista de dispositivos está vacía
como si no hubiera nada conectado. Los dispositivos siguen físicamente enchufados y
Windows los reconoce perfectamente, pero iCUE dice que no hay nada.

Pero esto no es solo un problema estético. iCUE gestiona también las **curvas de
velocidad de los ventiladores** conectados a los controladores (Commander Core XT e
iCUE LINK System Hub) y la **iluminación RGB de los módulos de RAM**. Cuando iCUE
pierde la comunicación, **todos esos perfiles dejan de aplicarse**: los ventiladores
caen a la configuración por defecto a velocidad fija predefinida y la RAM vuelve a 
su modo estático o apaga el RGB.

La solución temporal es cerrar iCUE y volvarlo a abrir. A veces hay que hacerlo dos
veces. Dependiendo de cuánto tardes en darte cuenta, llevas diez minutos trabajando
con el teclado en modo estático blanco y el AIO corriendo sin sus curvas de
refrigeración configuradas porque nada te avisó.

Esto ocurre de forma reproducible:

- Al despertar el PC del modo suspensión (S3/sleep)
- Al reanudar desde hibernación
- Al encender el monitor tras haber estado apagado
- Tras un evento de energía del sistema (reanudación desde bajo consumo)

---

## Por qué ocurre

iCUE 5 está dividido en dos capas que se comunican entre sí mediante IPC
(Inter-Process Communication): el servicio de bajo nivel que habla con el hardware USB
y la interfaz de usuario que muestra los dispositivos. Cuando el sistema entra en
suspensión y luego vuelve a despertar, el subsistema USB de Windows re-enumera los
dispositivos, pero iCUE pierde el estado de esa comunicación interna y no es capaz de
recuperarlo por sí solo.

El log de iCUE lo deja claro. En condiciones normales, una sesión sana tiene este
aspecto:

```
[...] Entering working state
[...] StartEnumeration finished
[...] cue.devices.set: K70 RGB PRO (...)
[...] Devices ready received from service
```

Tras despertar del sueño, en cambio:

```
[...] Leaving working state
[...] ConnectionLost
[...] StopEnumeration finished
[...] Disable all enumerators
```

El log registra que iCUE detectó una pérdida de conexión IPC y se desenganchó del
hardware. Mientras no se reinicie el proceso, los dispositivos permanecerán invisibles.

---

## Por qué las soluciones habituales NO funcionan

En Reddit y foros se repiten siempre las mismas sugerencias. Ninguna resuelve el
problema porque **todas atacan la capa de hardware**, pero el fallo ocurre en la capa
de software de iCUE.

### ❌ Deshabilitar la suspensión selectiva de USB

> Panel de control → Opciones de energía → Cambiar la configuración del plan →
> Configuración de USB → Configuración de suspensión selectiva de USB → **Deshabilitado**

La suspensión selectiva de USB permite que Windows suspenda individualmente cada
puerto USB que no esté en uso activo, para ahorrar energía. Deshabilitarla significa
que los puertos USB nunca se suspenderán.

**Por qué no funciona:** El problema no es que el dispositivo se desconecte del USB.
Tras despertar el PC, Windows vuelve a enumerar los dispositivos correctamente —
puedes verlo en el Administrador de dispositivos, siguen ahí. El fallo está en que
iCUE pierde su comunicación IPC interna y no la restituye. Aunque los puertos USB
nunca se duerman, iCUE seguirá fallando al despertar.

### ❌ Desmarcar "Permitir que el equipo apague este dispositivo para ahorrar energía"

> Administrador de dispositivos → [dispositivo Corsair] → Propiedades →
> Administración de energía → desmarcar la casilla

Esta opción le dice al driver USB que no apague el dispositivo cuando el sistema
reduzca la energía. Los dispositivos afectados son exactamente los detectados en este
sistema:

**Controladores USB (visibles en Administrador de dispositivos → árbol USB):**

| Hardware ID completo                   | Dispositivo                              | Función iCUE                                  |
|----------------------------------------|------------------------------------------|-----------------------------------------------|
| `USB\VID_1B1C&PID_0C2A&REV_0100`       | **CORSAIR iCUE COMMANDER CORE XT** (raíz)| Hub de ventiladores y canales RGB — nodo raíz |
| `USB\VID_1B1C&PID_0C2A&REV_0100&MI_00` | COMMANDER CORE XT — interfaz MI_00       | HID propietario Corsair (UP:FF42 U:0001)      |
| `USB\VID_1B1C&PID_0C2A&REV_0100&MI_01` | COMMANDER CORE XT — interfaz MI_01       | Control activo iCUE (UP:FF42 U:0002)          |
| `USB\VID_1B1C&PID_0C3F&REV_0100`       | **CORSAIR iCUE LINK System Hub** (raíz)  | Hub ecosistema iCUE LINK — nodo raíz          |
| `USB\VID_1B1C&PID_0C3F&REV_0100&MI_00` | iCUE LINK System Hub — interfaz MI_00    | HID propietario Corsair (UP:FF42 U:0001)      |
| `USB\VID_1B1C&PID_0C3F&REV_0100&MI_01` | iCUE LINK System Hub — interfaz MI_01    | Control activo iCUE (UP:FF42 U:0002)          |

**Memoria RAM (controlada vía SMBus/I2C, no aparece en el árbol USB):**

| Número de parte      | Dispositivo                                         | Función iCUE                   |
|----------------------|-----------------------------------------------------|--------------------------------|
| `CMT32GX5M2B5600C36` | **Corsair DOMINATOR TITANIUM** DDR5-5600 16 GB c/u  | Iluminación RGB de los módulos |

> **VID `1B1C`** = Corsair Memory Inc. (Vendor ID oficial USB).  
> **`UP:FF42`** es la página de uso HID propietaria de Corsair. Solo iCUE sabe
> interpretar los mensajes de esta interfaz; cuando iCUE pierde la comunicación IPC,
> los dispositivos quedan completamente inoperativos hasta que el proceso se reinicia.
>
> La RAM **no tiene ninguna entrada en el árbol USB** porque iCUE la controla
> directamente mediante el bus SMBus/I2C de la placa base, accediendo a los registros
> internos de los módulos sin pasar por el subsistema USB de Windows. Esto significa
> que la casilla "Permitir que el equipo apague este dispositivo" ni siquiera existe
> para ella — su iluminación también desaparece al fallar el IPC de iCUE, y tampoco
> se puede "arreglar" con ningún ajuste de energía del sistema.

**Por qué no funciona:** Igual que antes, el hardware no se desconecta físicamente.
Es iCUE quien pierde el hilo internamente. Puedes desmarcar todas las casillas de
administración de energía de todos los dispositivos Corsair, y al día siguiente
volverás a tener el mismo problema.

### ❌ Reiniciar el servicio de Corsair

Algunos posts sugieren reiniciar el servicio `CorsairService` o `CorsairLLAService`
desde el Administrador de tareas o `services.msc`. Esto puede funcionar
ocasionalmente pero es inconsistente y requiere intervención manual. Además, en
algunos casos reiniciar el servicio sin reiniciar el proceso principal de iCUE no
resuelve el fallo de IPC.

### ❌ Reinstalar iCUE / actualizar drivers

El problema lleva presente en iCUE 5 desde sus primeras versiones. Las
actualizaciones de iCUE no lo corrigen de forma permanente; si no, ya estaría
resuelto. Reinstalar no cambia el comportamiento del software ante eventos de
energía del sistema.

---

## La solución real: reiniciar iCUE

Lo único que funciona consistentemente es matar el proceso `iCUE.exe` y volverlo a
lanzar. Cuando iCUE arranca desde cero, inicializa su capa IPC limpiamente y
encuentra los dispositivos sin problema.

**iCUE Watchdog** automatiza exactamente eso. Lee el propio log de iCUE para
detectar si hay un fallo IPC real, y si lo hay, mata el proceso y lo relanza —
sin intervención manual, sin que tengas que darte cuenta de que algo fue mal.

---

## Cómo funciona

El script `Restore.ps1` realiza las siguientes comprobaciones:

1. Localiza el log más reciente de iCUE (en `%LOCALAPPDATA%\Corsair\Logs\CUE5\` si
   iCUE corre sin privilegios, o en `C:\ProgramData\Corsair\Logs\CUE5\` si corre
   elevado).
2. Lee las últimas 200 líneas del log y busca los marcadores de estado de la
   comunicación IPC:
   - `Entering working state` / `StartEnumeration finished` → iCUE OK
   - `Leaving working state` / `ConnectionLost` / `StopEnumeration finished` /
     `Disable all enumerators` → iCUE ha perdido el IPC
3. Si el último evento es de tipo "salida" o "pérdida", el fallo está confirmado:
   mata `iCUE.exe` y lo relanza con `Shell.Application.ShellExecute` para asegurarse
   de que arranca sin privilegios de administrador (necesario para que iCUE pueda
   comunicarse con los dispositivos USB correctamente).
4. Si iCUE se resiste a cerrarse, solicita elevación de administrador
   **exclusivamente** para matar el proceso, y después continúa sin privilegios.

La tarea programada lanza el script automáticamente en dos situaciones:

- **Al desbloquear la sesión** — cubre el caso de encender el monitor y desbloquear
  Windows.
- **Evento Power Troubleshooter, ID 1** — se dispara cuando Windows registra una
  reanudación desde suspensión o hibernación.

---

## Instalación

### Opción A — Todo en uno (recomendado)

Descarga `iCUE-Watchdog.cmd` de la sección [Releases] y ejecútalo con doble clic.
Aparecerá un menú:

```
==========================================
      iCUE Watchdog  v1.0
==========================================

 [1] Install   (register Scheduled Task)
 [2] Restore   (force restart)
 [3] Uninstall (remove task and files)
 [0] Exit
```

Selecciona **[1] Install**. Se pedirá confirmación de UAC para registrar la tarea
programada. Después de instalar, el fixer se ejecutará automáticamente en cada
reanudación.

### Opción B — Archivos separados

Descarga los archivos de `Separate-Files-Version\`:

| Archivo          | Descripción                                          |
|------------------|------------------------------------------------------|
| `Install.cmd`    | Instala la tarea programada (requiere admin via UAC) |
| `Restore.cmd`    | Fuerza un ciclo de reinicio manual de iCUE           |
| `Uninstall.cmd`  | Elimina la tarea y los archivos instalados           |

### Dónde se instala

El instalador copia `Restore.ps1` a:

```
%LOCALAPPDATA%\iCUE-Watchdog\Restore.ps1
```

Y registra la tarea programada `iCUE-Watchdog` con las siguientes propiedades:

- Se ejecuta con los privilegios mínimos necesarios (`LeastPrivilege`)
- Usa el token interactivo del usuario actual (no se ejecuta en segundo plano
  invisible)
- Se dispara en desbloqueo de sesión y en el evento de reanudación de energía

---

## Desinstalación

Ejecuta `iCUE-Watchdog.cmd → [3] Uninstall` o `Uninstall.cmd`. Se eliminará la tarea
programada y el directorio de instalación.

---

## Uso manual

Si quieres ejecutarlo sin esperar al próximo desbloqueo:

```cmd
REM Desde la carpeta de descarga:
Restore.cmd

REM Con reinicio forzado (sin leer el log):
Restore.cmd --force
```

---

## Requisitos

- Windows 10 / 11
- PowerShell 5.1 (incluido en Windows por defecto)
- iCUE 5 instalado en la ruta estándar
- Los periféricos Corsair deben estar conectados vía USB

---

## Seguridad

- El script **nunca** se ejecuta con permisos de administrador de forma permanente.
  La única excepción es el paso de matar el proceso si iCUE corre elevado, y para
  eso se abre un subproceso elevado que hace únicamente esa operación.
- No modifica el registro de Windows más allá de registrar la tarea programada.
- No toca los servicios de Corsair (solo mata `iCUE.exe`).
- No envía datos a ningún servidor externo.
- El código fuente está disponible en este repositorio para su revisión.

---

## Compilar desde el código fuente

```powershell
# Genera los archivos en build\
.\build.ps1

# Ejecuta los tests
.\test.ps1
```

Los archivos distribuibles se generan en `build\Separate-Files-Version\` y
`build\All-In-One-Version\`.

---

## Licencia

MIT — ver [LICENSE](LICENSE).

[Releases]: https://github.com/nyok1912/iCUE-watchdog/releases
