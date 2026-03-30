# zbar-killscreen.ps1 - Animated kill notification screen
# Launched in a new console when zbar terminates a game process

param(
    [string]$ProcessName = "UNKNOWN"
)

# === Unicode chars (defined via code points - no encoding issues) ===
$B   = [string][char]0x2588  # Full block
$UH  = [string][char]0x2580  # Upper half block
$LH  = [string][char]0x2584  # Lower half block
$SH  = [string][char]0x2591  # Light shade
$SH2 = [string][char]0x2592  # Medium shade
$HL  = [string][char]0x2550  # Double horizontal
$TLC = [string][char]0x2554  # Top-left corner
$TRC = [string][char]0x2557  # Top-right corner
$BLC = [string][char]0x255A  # Bottom-left corner
$BRC = [string][char]0x255D  # Bottom-right corner
$DH  = [string][char]0x2500  # Thin horizontal
$BUL = [string][char]0x2022  # Bullet

# === ANSI setup ===
$esc = [char]27
$RESET   = "$($esc)[0m"
$BOLD    = "$($esc)[1m"

# Color palette - deep burgundy / crimson
$DARK    = "$($esc)[38;2;55;5;10m"
$BURG    = "$($esc)[38;2;120;15;22m"
$RED     = "$($esc)[38;2;160;25;32m"
$CRIM    = "$($esc)[38;2;200;38;42m"
$BRIGHT  = "$($esc)[38;2;235;60;55m"
$FLASH   = "$($esc)[38;2;255;90;70m"
$EMBER   = "$($esc)[38;2;210;130;45m"
$DIM     = "$($esc)[38;2;75;45;45m"
$GHOST   = "$($esc)[38;2;45;20;22m"

# === Console init ===
$Host.UI.RawUI.WindowTitle = "Z B A R"
$Host.UI.RawUI.BackgroundColor = "Black"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { [Console]::CursorVisible = $false } catch {}
try {
    if ([Console]::WindowWidth -lt 100) {
        [Console]::BufferWidth = 120
        [Console]::WindowWidth = 120
    }
} catch {}
Clear-Host

$w = try { [Console]::WindowWidth } catch { 120 }
$h = try { [Console]::WindowHeight } catch { 30 }

# === Helpers ===
function Ctr([string]$text) {
    $raw = $text -replace "$([char]27)\[[^m]*m", ''
    $pad = [Math]::Max(0, [Math]::Floor(($w - $raw.Length) / 2))
    return (" " * $pad) + $text
}

function Art([string]$tpl) {
    return $tpl.Replace('#', $B).Replace('^', $UH).Replace('~', $LH)
}

function MakeColor([int]$r, [int]$g, [int]$b) {
    return "$($esc)[38;2;${r};${g};${b}m"
}

# ================================================================
#  ART DATA  (# = full block, ^ = upper half, ~ = lower half)
# ================================================================

$zbarArt = @(
    '  ##################    ################     ###############     ################  '
    '  ##################    #################    ################    #################  '
    '              ######    ######      ######   ######    ######    ######      ###### '
    '            ######      ######      ######   ######    ######    ######      ###### '
    '          ######        #################    ################    #################  '
    '        ######          ##################   #################   ################   '
    '      ######            ######      ######   ######      ######  ######   ######    '
    '    ######              ######      ######   ######      ######  ######    ######   '
    '  ##################    #################    ######      ######  ######     ######  '
    '  ##################    ################     ######      ######  ######      ###### '
)

$samuraiArt = @(
    '                            ~##~                            '
    '                           ######                           '
    '                          ########                          '
    '                       ^^^^######^^^^                       '
    '               ################################             '
    '                       ^############^                       '
    '                        ############                        '
    '                    ######################                  '
    '                   ##   ##############  ##                  '
    '                  ##     ############    ##                 '
    '                 ##       ########       ##                 '
    '                 ##       ###  ###       ##                 '
    '                  ##      ########      ##                  '
    '                   ##    ##########    ##                   '
    '                    ##  ############  ##                    '
    '                     ##################                    '
    '                    #####          #####                    '
    '                   ####              ####                   '
    '                  ####                ####                  '
    '                 #####                #####                 '
    '                 ^^^^^                ^^^^^                 '
)

# ================================================================
#  ANIMATION
# ================================================================

# -- Phase 1: Dark fog sweep --
$fogPool = @($SH, $SH, $SH2, ' ', ' ', ' ', ' ', ' ')
$rand = [System.Random]::new()
for ($row = 0; $row -lt [Math]::Min($h, 30); $row++) {
    $sb = [System.Text.StringBuilder]::new($w)
    for ($col = 0; $col -lt $w; $col++) {
        [void]$sb.Append($fogPool[$rand.Next($fogPool.Count)])
    }
    Write-Host "$GHOST$($sb.ToString())$RESET" -NoNewline
    Start-Sleep -Milliseconds 5
}
Start-Sleep -Milliseconds 250
Clear-Host

# -- Phase 2: Top border --
$bLen = [Math]::Min($w - 6, 88)
$topBorder = $TLC + ($HL * $bLen) + $TRC
Write-Host ""
Write-Host (Ctr "$BOLD$CRIM$topBorder$RESET")
Write-Host ""
Start-Sleep -Milliseconds 120

# -- Phase 3: ZBAR title (gradient reveal) --
$zColors = @($DARK, $BURG, $RED, $RED, $CRIM, $CRIM, $BRIGHT, $BRIGHT, $CRIM, $RED)
for ($i = 0; $i -lt $zbarArt.Count; $i++) {
    $c = if ($i -lt $zColors.Count) { $zColors[$i] } else { $RED }
    Write-Host (Ctr "$BOLD$c$(Art $zbarArt[$i])$RESET")
    Start-Sleep -Milliseconds 55
}
Start-Sleep -Milliseconds 250

# -- Phase 4: Samurai (center-bright gradient) --
Write-Host ""
$sTotal = $samuraiArt.Count
for ($i = 0; $i -lt $sTotal; $i++) {
    $norm = $i / [Math]::Max(1, $sTotal - 1)
    $bright = 1.0 - [Math]::Abs($norm - 0.45) * 1.8
    $bright = [Math]::Max(0.2, [Math]::Min(1.0, $bright))
    $cr = [int](80 + 160 * $bright)
    $cg = [int](10 + 45 * $bright)
    $cb = [int](15 + 30 * $bright)
    $lc = MakeColor $cr $cg $cb
    Write-Host (Ctr "$lc$(Art $samuraiArt[$i])$RESET")
    Start-Sleep -Milliseconds 30
}
Start-Sleep -Milliseconds 250

# -- Phase 5: Kill target --
Write-Host ""
$killTarget = $ProcessName.ToUpper()
$killStr = "[  $killTarget  ]  $DH$DH  TERMINATED"
Write-Host (Ctr "$BOLD$EMBER$killStr$RESET")
Start-Sleep -Milliseconds 150

# -- Phase 6: Divider --
Write-Host ""
$divider = "$DH$DH$DH $($HL * 44) $DH$DH$DH"
Write-Host (Ctr "$DIM$divider$RESET")
Start-Sleep -Milliseconds 200

# -- Phase 7: Tagline (typewriter effect) --
Write-Host ""
$tagline = "Z B A R   E N G A G E D   $BUL   F O R G E D   B Y   Z E I N"
$padN = [Math]::Max(0, [Math]::Floor(($w - $tagline.Length) / 2))
$padS = " " * $padN
[Console]::Write($padS)
$tagRow = [Console]::CursorTop
foreach ($ch in $tagline.ToCharArray()) {
    [Console]::Write("$BOLD$CRIM$ch$RESET")
    if ($ch -ne ' ') { Start-Sleep -Milliseconds 20 }
}
[Console]::WriteLine()
Write-Host ""

# -- Phase 8: Bottom border --
$botBorder = $BLC + ($HL * $bLen) + $BRC
Write-Host (Ctr "$BOLD$CRIM$botBorder$RESET")
Write-Host ""
# -- Hold and close --
Start-Sleep -Seconds 8
try { [Console]::CursorVisible = $true } catch {}
