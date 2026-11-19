param(
    [int]$Port = 8888
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$CityCache = @{}

function Escape-Xml([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return "" }
    return [System.Security.SecurityElement]::Escape($s)
}

function Map-WmoToAccu([int]$code, [int]$isDay = 1) {
    switch ($code) {
        0 { return @{ icon = $(if ($isDay) { 1 } else { 33 }); text = $(if ($isDay) { "Soleado" } else { "Despejado" }) } }
        1 { return @{ icon = $(if ($isDay) { 2 } else { 34 }); text = "Mayormente despejado" } }
        2 { return @{ icon = $(if ($isDay) { 3 } else { 35 }); text = "Parcialmente nublado" } }
        3 { return @{ icon = 7; text = "Nublado" } }
        45 { return @{ icon = 11; text = "Niebla" } }
        48 { return @{ icon = 11; text = "Niebla" } }
        51 { return @{ icon = 12; text = "Llovizna ligera" } }
        53 { return @{ icon = 12; text = "Llovizna" } }
        55 { return @{ icon = 12; text = "Llovizna densa" } }
        61 { return @{ icon = 14; text = "Lluvia ligera" } }
        63 { return @{ icon = 18; text = "Lluvia" } }
        65 { return @{ icon = 18; text = "Lluvia fuerte" } }
        71 { return @{ icon = 22; text = "Nieve ligera" } }
        73 { return @{ icon = 22; text = "Nieve" } }
        75 { return @{ icon = 22; text = "Nieve fuerte" } }
        80 { return @{ icon = 14; text = "Chubascos" } }
        81 { return @{ icon = 18; text = "Chubascos fuertes" } }
        82 { return @{ icon = 18; text = "Tormenta de lluvia" } }
        95 { return @{ icon = 15; text = "Tormenta electrica" } }
        96 { return @{ icon = 15; text = "Tormenta con granizo" } }
        99 { return @{ icon = 15; text = "Tormenta fuerte" } }
        default { return @{ icon = $(if ($isDay) { 3 } else { 35 }); text = "Parcialmente nublado" } }
    }
}

function Deg-ToDir([double]$deg) {
    $dirs = @("N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW")
    $idx = [int][math]::Floor((($deg + 11.25) % 360) / 22.5)
    return $dirs[$idx]
}

function Parse-Query([string]$q) {
    $map = @{}
    if ([string]::IsNullOrEmpty($q)) { return $map }
    foreach ($pair in $q.TrimStart('?').Split('&')) {
        if ($pair -eq "") { continue }
        $kv = $pair.Split('=', 2)
        $k = [Uri]::UnescapeDataString($kv[0])
        $v = if ($kv.Length -gt 1) { [Uri]::UnescapeDataString($kv[1].Replace('+', ' ')) } else { "" }
        $map[$k] = $v
    }
    return $map
}

function Fetch-Json([string]$url) {
    $json = & curl.exe -4 -s --max-time 10 "$url"
    if ([string]::IsNullOrWhiteSpace($json)) { throw "Empty response from $url" }
    return ($json | ConvertFrom-Json)
}

function Handle-CityFind([hashtable]$q) {
    $loc = $q["location"]
    if ([string]::IsNullOrWhiteSpace($loc)) { $loc = "Mexico" }
    $url = "https://geocoding-api.open-meteo.com/v1/search?name=$([Uri]::EscapeDataString($loc))&count=10&language=es&format=json"
    $resp = Fetch-Json $url
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0" encoding="utf-8"?><adc_database><citylist intl="1">')
    if ($resp.results) {
        foreach ($r in $resp.results) {
            $id = "cityId:$($r.id)"
            $CityCache[$id] = @{
                lat = [double]$r.latitude
                lon = [double]$r.longitude
                city = [string]$r.name
                adminArea = [string]$r.admin1
                country = [string]$r.country
                countryCode = [string]$r.country_code
            }
            $city = Escape-Xml $r.name
            $admin = Escape-Xml $r.admin1
            $country = Escape-Xml $r.country
            $cc = Escape-Xml $r.country_code
            [void]$sb.Append("<location city=`"$city`" adminArea=`"$admin`" state=`"$admin`" country=`"$country`" countryCode=`"$cc`" location=`"$id`" lat=`"$($r.latitude)`" lon=`"$($r.longitude)`" />")
        }
    }
    [void]$sb.Append('</citylist></adc_database>')
    return $sb.ToString()
}

function Handle-WeatherData([hashtable]$q) {
    $metric = if ($q["metric"] -eq "0") { 0 } else { 1 }
    $lat = 19.43
    $lon = -99.13
    $city = "Mi Ciudad"
    $admin = ""
    $country = ""

    if ($q.ContainsKey("latitude") -and $q.ContainsKey("longitude")) {
        $lat = [double]$q["latitude"]
        $lon = [double]$q["longitude"]
        $city = "Ubicacion actual"
    } elseif ($q.ContainsKey("location") -and $CityCache.ContainsKey($q["location"])) {
        $c = $CityCache[$q["location"]]
        $lat = $c.lat
        $lon = $c.lon
        $city = $c.city
        $admin = $c.adminArea
        $country = $c.country
    }

    $unitParams = if ($metric -eq 0) { "&temperature_unit=fahrenheit&wind_speed_unit=mph" } else { "" }
    $url = "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,surface_pressure,wind_speed_10m,wind_direction_10m,wind_gusts_10m&hourly=temperature_2m,apparent_temperature,precipitation_probability,weather_code,wind_speed_10m,wind_direction_10m&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_probability_max,wind_speed_10m_max,wind_direction_10m_dominant,wind_gusts_10m_max&timezone=auto&forecast_days=10$unitParams"
    $w = Fetch-Json $url

    $cur = $w.current
    $isDay = [int]$cur.is_day
    $mapped = Map-WmoToAccu ([int]$cur.weather_code) $isDay
    $tempUnit = if ($metric -eq 1) { "C" } else { "F" }
    $speedUnit = if ($metric -eq 1) { "km/h" } else { "mph" }
    $gmtOffset = [math]::Round(([double]$w.utc_offset_seconds) / 3600.0, 2)
    $obsTime = ([datetime]$cur.time).ToString("HH:mm")

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0" encoding="utf-8"?><adc_database>')
    [void]$sb.Append("<units><temp>$tempUnit</temp><dist>km</dist><speed>$speedUnit</speed><pres>hPa</pres><prec>mm</prec></units>")
    [void]$sb.Append("<local><city>$(Escape-Xml $city)</city><adminArea>$(Escape-Xml $admin)</adminArea><country>$(Escape-Xml $country)</country><lat>$lat</lat><lon>$lon</lon><currentGmtOffset>$gmtOffset</currentGmtOffset></local>")
    [void]$sb.Append("<currentconditions daylight=`"$isDay`">")
    [void]$sb.Append("<observationtime>$obsTime</observationtime>")
    [void]$sb.Append("<pressure>$([math]::Round([double]$cur.surface_pressure))</pressure>")
    [void]$sb.Append("<temperature>$([math]::Round([double]$cur.temperature_2m))</temperature>")
    [void]$sb.Append("<realfeel>$([math]::Round([double]$cur.apparent_temperature))</realfeel>")
    [void]$sb.Append("<humidity>$([math]::Round([double]$cur.relative_humidity_2m))%</humidity>")
    [void]$sb.Append("<weathertext>$(Escape-Xml $mapped.text)</weathertext>")
    [void]$sb.Append("<weathericon>$($mapped.icon)</weathericon>")
    [void]$sb.Append("<windgusts>$([math]::Round([double]$cur.wind_gusts_10m))</windgusts>")
    [void]$sb.Append("<windspeed>$([math]::Round([double]$cur.wind_speed_10m))</windspeed>")
    [void]$sb.Append("<winddirection>$(Deg-ToDir ([double]$cur.wind_direction_10m))</winddirection>")
    [void]$sb.Append("<uvindex>3</uvindex>")
    [void]$sb.Append("<windchill>$([math]::Round([double]$cur.apparent_temperature))</windchill>")
    [void]$sb.Append("</currentconditions>")

    [void]$sb.Append("<forecast>")
    $days = $w.daily.time.Count
    for ($i = 0; $i -lt $days; $i++) {
        $dNum = $i + 1
        $dt = ([datetime]$w.daily.time[$i]).ToString("MM/dd/yyyy")
        $sr = ([datetime]$w.daily.sunrise[$i]).ToString("HH:mm")
        $ss = ([datetime]$w.daily.sunset[$i]).ToString("HH:mm")
        $dm = Map-WmoToAccu ([int]$w.daily.weather_code[$i]) 1
        $nm = Map-WmoToAccu ([int]$w.daily.weather_code[$i]) 0
        $hi = [math]::Round([double]$w.daily.temperature_2m_max[$i])
        $lo = [math]::Round([double]$w.daily.temperature_2m_min[$i])
        $ws = [math]::Round([double]$w.daily.wind_speed_10m_max[$i])
        $wg = [math]::Round([double]$w.daily.wind_gusts_10m_max[$i])
        $wd = Deg-ToDir ([double]$w.daily.wind_direction_10m_dominant[$i])
        $uv = [math]::Round([double]$w.daily.uv_index_max[$i])
        [void]$sb.Append("<day number=`"$dNum`"><obsdate>$dt</obsdate><sunrise>$sr</sunrise><sunset>$ss</sunset>")
        [void]$sb.Append("<daytime><txtshort>$(Escape-Xml $dm.text)</txtshort><txtlong>$(Escape-Xml $dm.text)</txtlong><weathericon>$($dm.icon)</weathericon><hightemperature>$hi</hightemperature><lowtemperature>$lo</lowtemperature><realfeel>$hi</realfeel><windspeed>$ws</windspeed><winddirection>$wd</winddirection><windgust>$wg</windgust><maxuv>$uv</maxuv></daytime>")
        [void]$sb.Append("<nighttime><txtshort>$(Escape-Xml $nm.text)</txtshort><txtlong>$(Escape-Xml $nm.text)</txtlong><weathericon>$($nm.icon)</weathericon><hightemperature>$hi</hightemperature><lowtemperature>$lo</lowtemperature><realfeel>$lo</realfeel><windspeed>$ws</windspeed><winddirection>$wd</winddirection><windgust>$wg</windgust><maxuv>0</maxuv></nighttime>")
        [void]$sb.Append("</day>")
    }
    [void]$sb.Append("</forecast>")

    [void]$sb.Append("<hourly>")
    $nowHour = 0
    $maxH = [math]::Min(24, $w.hourly.time.Count)
    for ($h = 0; $h -lt $maxH; $h++) {
        $hm = Map-WmoToAccu ([int]$w.hourly.weather_code[$h]) 1
        $ht = [math]::Round([double]$w.hourly.temperature_2m[$h])
        $hf = [math]::Round([double]$w.hourly.apparent_temperature[$h])
        $hp = [int]$w.hourly.precipitation_probability[$h]
        $hws = [math]::Round([double]$w.hourly.wind_speed_10m[$h])
        $hwd = Deg-ToDir ([double]$w.hourly.wind_direction_10m[$h])
        $hNum = ([datetime]$w.hourly.time[$h]).Hour
        [void]$sb.Append("<hour number=`"$hNum`"><weathericon>$($hm.icon)</weathericon><temperature>$ht</temperature><realfeel>$hf</realfeel><precip>$hp</precip><windspeed>$hws</windspeed><winddirection>$hwd</winddirection><txtshort>$(Escape-Xml $hm.text)</txtshort></hour>")
    }
    [void]$sb.Append("</hourly>")
    [void]$sb.Append('</adc_database>')
    return $sb.ToString()
}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
$listener.Start()
Write-Host "Servidor de Clima BB10 escuchando en puerto $Port (Ctrl+C para detener)..." -ForegroundColor Green

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 4096, $true)
            $reqLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($reqLine)) { $client.Close(); continue }
            while ($true) {
                $h = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($h)) { break }
            }
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $reqLine"
            $parts = $reqLine.Split(' ')
            $rawUrl = if ($parts.Length -ge 2) { $parts[1] } else { "/" }
            $pathAndQuery = if ($rawUrl -match '^https?://[^/]+(.*)$') { $matches[1] } else { $rawUrl }
            $pq = $pathAndQuery.Split('?', 2)
            $path = $pq[0]
            $query = if ($pq.Length -gt 1) { Parse-Query $pq[1] } else { @{} }

            $body = $null
            if ($path -like "*city-find.asp*") {
                $body = Handle-CityFind $query
            } elseif ($path -like "*weather-data.asp*") {
                $body = Handle-WeatherData $query
            }

            if ($null -ne $body) {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $header = "HTTP/1.1 200 OK`r`nContent-Type: text/xml; charset=utf-8`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
                $hBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
                $stream.Write($hBytes, 0, $hBytes.Length)
                $stream.Write($bytes, 0, $bytes.Length)
            } else {
                $msg = "BB10 Weather Bridge Ready"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
                $header = "HTTP/1.1 200 OK`r`nContent-Type: text/plain`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
                $hBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
                $stream.Write($hBytes, 0, $hBytes.Length)
                $stream.Write($bytes, 0, $bytes.Length)
            }
            $stream.Flush()
        } catch {
            Write-Host "Error: $_" -ForegroundColor Red
        } finally {
            $client.Close()
        }
    }
} finally {
    $listener.Stop()
}
