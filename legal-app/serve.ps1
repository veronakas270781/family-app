# Lawyer.AI -- local server with a built-in proxy to adilet.zan.kz
# The proxy is required because the browser cannot reach adilet directly
# (CORS), and adilet serves an incomplete TLS certificate chain.

# Accept adilet's incomplete certificate chain
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:3355/")
$listener.Start()
Write-Host "Lawyer.AI running: http://localhost:3355/"
Write-Host "adilet.zan.kz proxy active at /api/fetch. Close this window to stop."

# Hosts allowed to be proxied (only official RK legislation sources)
$allowedHostPattern = '^(www\.)?(adilet\.zan\.kz|adilet\.zan\.gov\.kz|zan\.kz)$'

while ($listener.IsListening) {
    $ctx  = $listener.GetContext()
    $req  = $ctx.Request
    $resp = $ctx.Response
    $path = $req.Url.LocalPath

    try {
        if ($path -eq "/api/fetch") {
            # Proxy: GET /api/fetch?url=<official adilet url>
            $target = $req.QueryString["url"]
            $ok = $false
            if ($target) {
                try { $u = [System.Uri]$target; $ok = ($u.Scheme -in @('http','https')) -and ($u.Host -match $allowedHostPattern) } catch { $ok = $false }
            }
            if (-not $ok) {
                $resp.StatusCode = 403
                $b = [System.Text.Encoding]::UTF8.GetBytes("Forbidden: only adilet.zan.kz / zan.kz are allowed")
                $resp.OutputStream.Write($b, 0, $b.Length)
            } else {
                try {
                    $wc = New-Object System.Net.WebClient
                    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (LawAI local proxy)")
                    $bytes = $wc.DownloadData($target)
                    $resp.ContentType = "text/plain; charset=utf-8"
                    $resp.AddHeader("Cache-Control", "no-store")
                    $resp.ContentLength64 = $bytes.Length
                    $resp.OutputStream.Write($bytes, 0, $bytes.Length)
                } catch {
                    $resp.StatusCode = 502
                    $b = [System.Text.Encoding]::UTF8.GetBytes("Proxy error: " + $_.Exception.Message)
                    $resp.OutputStream.Write($b, 0, $b.Length)
                }
            }
        }
        else {
            # Static files
            if ($path -eq "/" -or $path -eq "") { $path = "/index.html" }
            $file = Join-Path (Split-Path $MyInvocation.MyCommand.Path) $path.TrimStart("/")
            if (Test-Path $file) {
                $content = [System.IO.File]::ReadAllBytes($file)
                $ext = [System.IO.Path]::GetExtension($file)
                $mime = if ($ext -eq ".html") { "text/html; charset=utf-8" } elseif ($ext -eq ".js") { "application/javascript" } elseif ($ext -eq ".css") { "text/css" } else { "application/octet-stream" }
                $resp.ContentType = $mime
                $resp.ContentLength64 = $content.Length
                $resp.OutputStream.Write($content, 0, $content.Length)
            } else {
                $resp.StatusCode = 404
            }
        }
    } catch {
        try { $resp.StatusCode = 500 } catch {}
    } finally {
        $resp.OutputStream.Close()
    }
}
