# --- CONFIGURATION ---
# 1. Set the base path for your render farm folders.
$basePath = "your path"

# 2. Set the folder names.
$jobsFolder = Join-Path -Path $basePath -ChildPath "jobs_AE24"
$inProgressFolder = Join-Path -Path $basePath -ChildPath "InProgress"

# 3. Set the path to aerender.exe on THIS server.
$aerenderPath = "C:\Program Files\Adobe\Adobe After Effects 2024\Support Files\aerender.exe"

# 4. Set your Discord Webhook URL
$webhookUrl = "your discord webhook"

# --- DISCORD NOTIFICATION FUNCTION ---
function Send-DiscordNotification {
    param (
        [string]$Message,
        [string]$Color = "7506394" # Default color (blue-ish)
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $payload = @{
        embeds = @(
            @{                title = "Render Watcher Status"
                description = $Message
                color = $Color
                footer = @{
                    text = "Server: $env:COMPUTERNAME | $timestamp"
                }
            }
        )
    } | ConvertTo-Json -Depth 4

    try {
        Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $payload -ContentType 'application/json'
    } catch {
        Write-Host "[$timestamp] [ERROR] Failed to send Discord notification: $_" -ForegroundColor Red
    }
}


# --- SCRIPT ---
Write-Host "=========================================" -ForegroundColor Green
Write-Host "    SIMPLE RENDER WATCHER (PowerShell)   " -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Watching for FOLDERS in: $jobsFolder"
Write-Host "Press Ctrl+C to stop the watcher."
Write-Host ""

# --- Pre-flight checks ---
if (-not (Test-Path -Path $aerenderPath)) {
    $msg = "[ERROR] aerender.exe not found at '$($aerenderPath)'. Please check the path."
    Write-Host $msg -ForegroundColor Red
    Send-DiscordNotification -Message $msg -Color "15548997" # Red
    pause
    exit
}
if (-not (Test-Path -Path $basePath)) {
    $msg = "[ERROR] Base path not found at '$($basePath)'. Please ensure the path is correct and accessible."
    Write-Host $msg -ForegroundColor Red
    Send-DiscordNotification -Message $msg -Color "15548997" # Red
    pause
    exit
}

# Create folders if they don't exist
if (-not (Test-Path -Path $jobsFolder)) { New-Item -ItemType Directory -Path $jobsFolder | Out-Null }
if (-not (Test-Path -Path $inProgressFolder)) { New-Item -ItemType Directory -Path $inProgressFolder | Out-Null }

# --- Startup Notification ---
$startupMessage = "Render watcher script started. Watching for jobs in `{0}`." -f $jobsFolder
Write-Host $startupMessage
Send-DiscordNotification -Message $startupMessage -Color "3066993" # Green

# --- Main Loop ---
while ($true) {
    # Get the oldest FOLDER in the Jobs folder
    $jobFolder = Get-ChildItem -Path $jobsFolder -Directory | Sort-Object CreationTime | Select-Object -First 1

    if ($jobFolder) {
        $timestamp = Get-Date -Format "HH:mm:ss"
        $jobName = $jobFolder.Name
        $foundMsg = "[$timestamp] Found project folder: $jobName"
        Write-Host $foundMsg
        Send-DiscordNotification -Message ('Found project folder: `{0}`' -f $jobName)

        # Find the NEWEST .aep file inside that folder
        $aepFile = Get-ChildItem -Path $jobFolder.FullName -Filter "*.aep" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if (-not $aepFile) {
            $errorMsg = "[$timestamp] [ERROR] No .aep file found inside `$jobName`. Deleting folder."
            Write-Host $errorMsg -ForegroundColor Red
            Send-DiscordNotification -Message ('No .aep file found inside `{0}`. Deleting folder.' -f $jobName)
            Remove-Item -Recurse -Force -Path $jobFolder.FullName
            continue # Go to the next loop iteration
        }

        $aepName = $aepFile.Name
        Write-Host "[$timestamp] Found AEP to render: $aepName"

        # Move the entire project folder to InProgress
        $inProgressPath = Join-Path -Path $inProgressFolder -ChildPath $jobName
        Write-Host "[$timestamp] Moving project to InProgress folder..."
        Move-Item -Path $jobFolder.FullName -Destination $inProgressPath

        $renderAepPath = Join-Path -Path $inProgressPath -ChildPath $aepName

        $startRenderMsg = 'Starting render for: `{0}` from project `{1}`.' -f $aepName, $jobName
        Write-Host "[$timestamp] $startRenderMsg"
        Send-DiscordNotification -Message $startRenderMsg -Color "3447003" # Blue

        Write-Host "-------------------- RENDER LOG START --------------------" -ForegroundColor Cyan

        # Run aerender directly and stream its output to the console.
        & $aerenderPath -project "$renderAepPath" -sound ON

        Write-Host "-------------------- RENDER LOG END ----------------------" -ForegroundColor Cyan

        $timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "[$timestamp] Render finished."
        
        # Delete the project folder from InProgress to make way for the next job.
        Write-Host "[$timestamp] Deleting completed job folder..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force -Path $inProgressPath

        $completeMsg = 'Successfully rendered and completed job: `{0}`.' -f $jobName
        Write-Host "[$timestamp] Job complete. Looking for new jobs..."
        Send-DiscordNotification -Message $completeMsg -Color "3066993" # Green
        Write-Host ""

    } else {
        $timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "[$timestamp] No jobs found. Waiting..."
        Start-Sleep -Seconds 10
    }
}
