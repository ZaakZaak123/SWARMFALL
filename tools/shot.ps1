param([string]$Out = "shot.png", [double]$Scale = 0.5, [switch]$Viewport, [switch]$Screen)
# Screenshot of the Roblox Studio window via PrintWindow (works while other windows cover it).
# -Screen copies the visible screen area instead (PrintWindow returns a blank 3D view on some GPUs/sessions;
#   Studio must be the top window).
# -Viewport crops to the 3D view (Studio chrome trimmed by fixed margins measured on this machine).
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class W32 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
$p = Get-Process RobloxStudioBeta | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$r = New-Object W32+RECT
[W32]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
$w = $r.R - $r.L; $h = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc()
if ($Screen) {
  $g.ReleaseHdc($dc)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $h))
} else {
  [W32]::PrintWindow($p.MainWindowHandle, $dc, 2) | Out-Null
  $g.ReleaseHdc($dc)
}
$src = New-Object System.Drawing.Rectangle 0, 0, $w, $h
if ($Viewport) { $src = New-Object System.Drawing.Rectangle 12, 210, ($w - 12 - 190), ($h - 210 - 70) }
$sw = [int]($src.Width * $Scale); $sh = [int]($src.Height * $Scale)
$small = New-Object System.Drawing.Bitmap $sw, $sh
$g2 = [System.Drawing.Graphics]::FromImage($small)
$g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g2.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0, 0, $sw, $sh), $src, [System.Drawing.GraphicsUnit]::Pixel)
$small.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
"$w x $h -> $Out"
