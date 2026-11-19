# BB10 Weather Revival (2026) — Puente Open-Meteo para BlackBerry 10

Revive la aplicación nativa original de **Clima** (`sys.weather`) en **BlackBerry 10** (probado en **BlackBerry Passport SQW100-1**, OS `10.3.3.3216`) sin modificar ni recompilar el binario de la aplicación.

---

## ¿Cómo funciona?

Al inspeccionar la librería del sistema `/base/usr/lib/libweatherlib.so.1`, se encontró que la app de Clima de BB10 realiza peticiones **HTTP sin cifrar** a:

- `http://rimbb10.accu-weather.com/widget/rimbb10/city-find.asp?location=...&langid=...`
- `http://rimbb10.accu-weather.com/widget/rimbb10/weather-data.asp?location=...&langid=...&metric=...`
- `http://rimbb10.accu-weather.com/widget/rimbb10/weather-data.asp?latitude=...&longitude=...&langid=...&metric=...`

El script **`weather_server.ps1`** actúa como servidor proxy HTTP local en Windows (puerto `8888`):
1. Intercepta las peticiones dirigidas a `rimbb10.accu-weather.com`.
2. Consulta datos reales y gratuitos en **Open-Meteo** (`geocoding-api.open-meteo.com` y `api.open-meteo.com`) usando `curl.exe -4`.
3. Traduce la respuesta JSON al esquema **XML** exacto que espera `libweatherlib.so.1` (`<adc_database>`, `<citylist>`, `<currentconditions>`, `<forecast>`, `<hourly>`).

---

## Requisitos

- PC con **Windows 10 / Windows 11** (PowerShell 5.1+ y `curl.exe` integrado).
- Dispositivo **BlackBerry 10** conectado a la **misma red Wi-Fi** que el PC.

---

## Uso rápido

1. **Inicia el servidor en tu PC:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\weather_server.ps1
   ```
   *(Si el Firewall de Windows solicita permiso para redes privadas, selecciona **Permitir**).*

2. **Obtén la IP local Wi-Fi de tu PC** (por ejemplo con `ipconfig`, ej. `192.168.0.183`).

3. **Configura el Proxy HTTP en tu BlackBerry 10:**
   - Ve a **Configuración > Redes y conexiones > Wi-Fi**.
   - Entra a los ajustes avanzados de tu red Wi-Fi y activa **Usar proxy**.
   - **Servidor:** `<IP_DE_TU_PC>` (ej. `192.168.0.183`)
   - **Puerto:** `8888`
   - Guarda los cambios.

4. **Abre la app original de Clima en tu BlackBerry 10:**
   - Busca tu ciudad y selecciónala. Los datos actuales, pronóstico por hora y de 10 días cargarán en la interfaz nativa.

> **Nota:** Mientras el proxy esté activado en el Wi-Fi del teléfono, el resto de webs no cargarán porque este servidor responde únicamente a los endpoints de Clima. Desactiva **Usar proxy** cuando termines de actualizar o probar.

---

## Archivos incluidos

- `weather_server.ps1` — Servidor puente HTTP en PowerShell hacia Open-Meteo.
- `BB10_Weather_Revival_2026.pdf` — Guía técnica y de uso en formato PDF.
- `README.md` — Documentación principal del repositorio.
