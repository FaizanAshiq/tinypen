# drive.ps1 -Exe <Tinypen.exe> [-Shots <folder>]: runs Tinypen on a real Windows desktop, as CI's
# e2e job does, and drives it as a person would: the drawing hotkey, a stroke, Esc twice. Each step
# is checked on Tinypen's own windows and on the pixels on screen, with a screenshot kept.
param(
    [Parameter(Mandatory)] [string] $Exe,
    [string] $Shots = 'shots'
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Shots | Out-Null
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class Desk
{
    public class Win
    {
        public IntPtr Handle;
        public string Title;
        public int X, Y, Width, Height;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Box { public int Left, Top, Right, Bottom; }

    private delegate bool EnumProc(IntPtr window, IntPtr data);

    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] private static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] private static extern void mouse_event(uint flags, int x, int y, uint data, UIntPtr extra);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc proc, IntPtr data);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int max);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out Box box);

    private const uint KeyUp = 0x2, Move = 0x1, LeftDown = 0x2, LeftUp = 0x4, Absolute = 0x8000;

    /// <summary>The visible top level windows of one process, front to back.</summary>
    public static List<Win> Windows(int process)
    {
        var found = new List<Win>();
        EnumWindows(delegate (IntPtr window, IntPtr data)
        {
            uint owner;
            GetWindowThreadProcessId(window, out owner);
            if (owner != process || !IsWindowVisible(window)) return true;
            var title = new StringBuilder(512);
            GetWindowText(window, title, title.Capacity);
            Box box;
            GetWindowRect(window, out box);
            found.Add(new Win { Handle = window, Title = title.ToString(), X = box.Left, Y = box.Top,
                                Width = box.Right - box.Left, Height = box.Bottom - box.Top });
            return true;
        }, IntPtr.Zero);
        return found;
    }

    /// <summary>Holds each key down in order, then lets them go in reverse, as fingers would.</summary>
    public static void Keys(params byte[] keys)
    {
        foreach (var key in keys) { keybd_event(key, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(30); }
        for (var i = keys.Length - 1; i >= 0; i--) { keybd_event(keys[i], 0, KeyUp, UIntPtr.Zero); System.Threading.Thread.Sleep(30); }
    }

    /// <summary>The pointer to a pixel on the primary monitor.</summary>
    public static void MoveTo(int x, int y)
    {
        var width = GetSystemMetrics(0);
        var height = GetSystemMetrics(1);
        mouse_event(Move | Absolute, x * 65535 / (width - 1), y * 65535 / (height - 1), 0, UIntPtr.Zero);
    }

    /// <summary>A left drag in small steps, as a hand would make it.</summary>
    public static void Drag(int fromX, int fromY, int toX, int toY)
    {
        MoveTo(fromX, fromY);
        System.Threading.Thread.Sleep(150);
        mouse_event(LeftDown, 0, 0, 0, UIntPtr.Zero);
        for (var step = 1; step <= 24; step++)
        {
            System.Threading.Thread.Sleep(20);
            MoveTo(fromX + (toX - fromX) * step / 24, fromY + (toY - fromY) * step / 24);
        }
        System.Threading.Thread.Sleep(150);
        mouse_event(LeftUp, 0, 0, 0, UIntPtr.Zero);
    }
}
'@
[void][Desk]::SetProcessDPIAware()

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$Ctrl, $Shift, $Esc = 0x11, 0x10, 0x1B
$results = New-Object System.Collections.Generic.List[string]
$script:failed = $false
$script:shot = 0

# A check is a block that returns nothing when it holds, or what went wrong.
function Check([string] $name, [scriptblock] $check)
{
    try { $problem = & $check } catch { $problem = "$($_.Exception.GetType().Name): $($_.Exception.Message)" }
    if ($problem) { $script:failed = $true; $line = "FAILED  ${name}: $problem" } else { $line = "ok      $name" }
    $results.Add($line)
    Write-Host $line
}

# The first thing the block returns within the time, or nothing.
function Until([scriptblock] $condition, [double] $seconds = 10)
{
    $deadline = (Get-Date).AddSeconds($seconds)
    do
    {
        try { $value = & $condition } catch { $value = $null }
        if ($value) { return $value }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Grab
{
    $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Left, $screen.Top, 0, 0, $bitmap.Size)
    $graphics.Dispose()
    return $bitmap
}

function Shot([string] $name, $bitmap = $null)
{
    $script:shot++
    $taken = if ($bitmap) { $bitmap } else { Grab }
    $taken.Save((Join-Path $Shots ('{0}-{1}.png' -f $script:shot, $name)), [System.Drawing.Imaging.ImageFormat]::Png)
}

function Shown([string] $title) { [Desk]::Windows($script:app.Id) | Where-Object Title -eq $title | Select-Object -First 1 }

function IsRed($pixel) { $pixel.R -gt 200 -and $pixel.G -lt 120 -and $pixel.B -lt 120 }

Write-Host "Screen $($screen.Width) by $($screen.Height)"

# 1. Starting: Tinypen keeps running and shows nothing but its tray icon.

$script:app = Start-Process $Exe -PassThru
Start-Sleep -Seconds 3
Check 'Tinypen starts and keeps running' { if ($script:app.HasExited) { "exited with code $($script:app.ExitCode)" } }
Check 'nothing of it shows before the hotkey' {
    $shown = @([Desk]::Windows($script:app.Id))
    if ($shown.Count -gt 0) { ($shown | ForEach-Object { "'$($_.Title)' $($_.Width)x$($_.Height)" }) -join ', ' }
}
$before = Grab
Shot 'started' $before

# 2. Drawing mode: Ctrl+Shift+D covers the screen with the drawing layer and shows the toolbar.

[Desk]::Keys($Ctrl, $Shift, 0x44)
$layer = Until { [Desk]::Windows($script:app.Id) | Where-Object { $_.Title -eq 'Tinypen drawing' -and $_.Width -ge $screen.Width -and $_.Height -ge $screen.Height } | Select-Object -First 1 }
$toolbar = Until { Shown 'Tinypen toolbar' }
Start-Sleep -Milliseconds 500
Shot 'drawing-mode'
Check 'Ctrl+Shift+D covers the screen with the drawing layer' { if (-not $layer) { 'no drawing layer' } }
Check 'the toolbar shows at the top of the screen' {
    if (-not $toolbar) { return 'no toolbar' }
    if ($toolbar.Y -gt $screen.Height / 3) { "toolbar at $($toolbar.X),$($toolbar.Y)" }
}

# 3. A stroke: the pen draws in red where the pointer went, and the pointer stays drawing.

$y = [int]($screen.Height * 0.6)
[Desk]::Drag(200, $y, 700, $y)
Start-Sleep -Milliseconds 500
$drawn = Grab
Shot 'stroke' $drawn
Check 'a drag draws a red line under the pointer' {
    $pixel = $drawn.GetPixel(450, $y)
    if (-not (IsRed $pixel)) { "at 450,$y the screen shows $($pixel.Name), was $($before.GetPixel(450, $y).Name)" }
}
Check 'nothing is drawn away from the stroke' {
    $pixel = $drawn.GetPixel(450, $y - 60)
    if (IsRed $pixel) { "at 450,$($y - 60) the screen shows $($pixel.Name)" }
}

# 4. Esc erases what is drawn; a second Esc leaves drawing mode.

[Desk]::Keys($Esc)
Start-Sleep -Milliseconds 500
$erased = Grab
Shot 'erased' $erased
Check 'Esc erases the line' { $pixel = $erased.GetPixel(450, $y); if (IsRed $pixel) { "at 450,$y the line is still there" } }
Check 'the first Esc keeps drawing mode on' { if (-not (Shown 'Tinypen toolbar')) { 'the toolbar went' } }
[Desk]::Keys($Esc)
$left = Until { -not (Shown 'Tinypen toolbar') -and -not (Shown 'Tinypen drawing') } 5
Shot 'left'
Check 'a second Esc leaves drawing mode' { if (-not $left) { 'the toolbar or the drawing layer is still up' } }
Check 'Tinypen is still running' { if ($script:app.HasExited) { "exited with code $($script:app.ExitCode)" } }

Stop-Process -Id $script:app.Id -Force -ErrorAction SilentlyContinue

$results | Set-Content (Join-Path $Shots 'results.txt')
if ($env:GITHUB_STEP_SUMMARY) { $results | ForEach-Object { "    $_" } | Add-Content $env:GITHUB_STEP_SUMMARY }
$passed = @($results | Where-Object { $_ -like 'ok*' }).Count
Write-Host "$passed of $($results.Count) passed"
if ($script:failed) { exit 1 }
