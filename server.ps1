$port = 3000
$prefix = "http://127.0.0.1:$port/"
$baseDir = $PSScriptRoot
if (-not $baseDir) { $baseDir = "C:\Users\Dell\.gemini\antigravity\scratch\termos" }
$reviewsFile = Join-Path $baseDir "reviews.json"

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-Output "HTTP Server started at $prefix"
    Write-Output "Press Ctrl+C to stop the server."

    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $urlPath = $request.Url.AbsolutePath

        if ($urlPath -eq "/api/reviews") {
            if ($request.HttpMethod -eq "GET") {
                $json = if (Test-Path $reviewsFile) { [System.IO.File]::ReadAllText($reviewsFile, [System.Text.Encoding]::UTF8) } else { "[]" }
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.Headers.Add("Access-Control-Allow-Origin", "*")
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.OutputStream.Close()
                continue
            }

            if ($request.HttpMethod -eq "POST") {
                $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                $body = $reader.ReadToEnd()
                try {
                    $newRevObj = ConvertFrom-Json $body
                    $newReview = [PSCustomObject]@{
                        id = "rev-" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                        name = "$($newRevObj.name)".Trim()
                        email = "$($newRevObj.email)".Trim()
                        rating = [Math]::Max(1, [Math]::Min(5, [int]$newRevObj.rating))
                        category = if ($newRevObj.category) { $newRevObj.category } else { "review" }
                        categoryLabel = switch ($newRevObj.category) {
                            "question" { "Запитання консультанту" }
                            "suggestion" { "Пропозиція / Порада" }
                            default { "Відгук про використання" }
                        }
                        message = "$($newRevObj.message)".Trim()
                        date = (Get-Date).ToString("yyyy-MM-dd")
                    }

                    $existing = if (Test-Path $reviewsFile) { [System.IO.File]::ReadAllText($reviewsFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } else { @() }
                    $list = [System.Collections.ArrayList]@($existing)
                    $list.Insert(0, $newReview)

                    $outJson = $list | ConvertTo-Json -Depth 5
                    [System.IO.File]::WriteAllText($reviewsFile, $outJson, [System.Text.Encoding]::UTF8)

                    $resPayload = @{ success = $true; review = $newReview } | ConvertTo-Json
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($resPayload)
                    $response.StatusCode = 201
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.Headers.Add("Access-Control-Allow-Origin", "*")
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                } catch {
                    $errPayload = @{ error = "Invalid data format" } | ConvertTo-Json
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($errPayload)
                    $response.StatusCode = 400
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
                $response.OutputStream.Close()
                continue
            }
        }

        # Static files
        $relPath = if ($urlPath -eq "/" -or [string]::IsNullOrWhiteSpace($urlPath)) { "index.html" } else { $urlPath.TrimStart('/') }
        $filePath = Join-Path $baseDir $relPath

        if (Test-Path $filePath -PathType Leaf) {
            $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
            $mime = switch ($ext) {
                ".html" { "text/html; charset=utf-8" }
                ".css"  { "text/css; charset=utf-8" }
                ".js"   { "application/javascript; charset=utf-8" }
                ".json" { "application/json; charset=utf-8" }
                ".png"  { "image/png" }
                ".jpg"  { "image/jpeg" }
                ".jpeg" { "image/jpeg" }
                ".webp" { "image/webp" }
                ".svg"  { "image/svg+xml" }
                default { "application/octet-stream" }
            }

            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $response.ContentType = $mime
            $response.ContentLength64 = $bytes.Length
            $response.StatusCode = 200
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $response.StatusCode = 404
            $errBytes = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
            $response.ContentType = "text/plain; charset=utf-8"
            $response.ContentLength64 = $errBytes.Length
            $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
        }
        $response.OutputStream.Close()
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
