<#
  set-refresh.ps1 — change display refresh rate with NO third-party tools
  (no nircmd, no ChangeScreenResolution). Uses the documented Win32
  ChangeDisplaySettingsEx API.

  USAGE:
    .\set-refresh.ps1 -Get          # print current refresh rate (integer Hz)
    .\set-refresh.ps1 -List         # list every mode the driver exposes
    .\set-refresh.ps1 -Hz 23        # 23 = 23.976 on NVIDIA (film cadence)
    .\set-refresh.ps1 -Hz 60
    .\set-refresh.ps1 -Hz 60 -Width 3840 -Height 2160

  NOTE: 23.976 usually has to be created as a custom resolution in the
  NVIDIA Control Panel first, otherwise the driver has nothing to switch
  to (it is often absent from the TV's EDID). True 24.000 usually exists.

  Exit code 0 = success, 1 = mode not available / failed.
#>

[CmdletBinding()]
param(
    [int]$Hz,
    [int]$Width,
    [int]$Height,
    [string]$Device,   # e.g. \\.\DISPLAY1 ; default = primary
    [switch]$List,
    [switch]$Get
)

$ErrorActionPreference = 'Stop'

# Win32 wants NULL for "current display"; an unset [string] param in PS is ""
# (not NULL), which breaks the call.
if ([string]::IsNullOrWhiteSpace($Device)) { $Device = $null }

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion; public short dmDriverVersion; public short dmSize;
    public short dmDriverExtra; public int dmFields;
    public int dmPositionX; public int dmPositionY;
    public int dmDisplayOrientation; public int dmDisplayFixedOutput;
    public short dmColor; public short dmDuplex; public short dmYResolution;
    public short dmTTOption; public short dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth;
    public int dmPelsHeight; public int dmDisplayFlags; public int dmDisplayFrequency;
    public int dmICMMethod; public int dmICMIntent; public int dmMediaType;
    public int dmDitherType; public int dmReserved1; public int dmReserved2;
    public int dmPanningWidth; public int dmPanningHeight;
}

public class Disp {
    [DllImport("user32.dll")]
    public static extern int EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
    [DllImport("user32.dll")]
    public static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr p);
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int CDS_UPDATEREGISTRY = 0x01;
    public const int DISP_CHANGE_SUCCESSFUL = 0;
}
"@

function Get-Current {
    param([string]$Dev)
    $dm = New-Object DEVMODE
    $dm.dmSize = [int16][System.Runtime.InteropServices.Marshal]::SizeOf([type]'DEVMODE')
    [void][Disp]::EnumDisplaySettings($Dev, [Disp]::ENUM_CURRENT_SETTINGS, [ref]$dm)
    return $dm
}

if ($Get) {
    $cur = Get-Current -Dev $Device
    Write-Output $cur.dmDisplayFrequency
    exit 0
}

if ($List) {
    $dm = New-Object DEVMODE
    $dm.dmSize = [int16][System.Runtime.InteropServices.Marshal]::SizeOf([type]'DEVMODE')
    $i = 0; $seen = @{}
    while ([Disp]::EnumDisplaySettings($Device, $i, [ref]$dm) -ne 0) {
        if ($dm.dmBitsPerPel -ge 32) {
            $k = "$($dm.dmPelsWidth)x$($dm.dmPelsHeight)@$($dm.dmDisplayFrequency)"
            if (-not $seen.ContainsKey($k)) { $seen[$k] = $true }
        }
        $i++
    }
    $seen.Keys | Sort-Object | ForEach-Object { $_ }
    $cur = Get-Current -Dev $Device
    Write-Output "current: $($cur.dmPelsWidth)x$($cur.dmPelsHeight)@$($cur.dmDisplayFrequency)"
    exit 0
}

if (-not $Hz) { Write-Error "Pass -Hz <rate>, -Get or -List"; exit 1 }

$dm = Get-Current -Dev $Device
$oldHz = $dm.dmDisplayFrequency
if ($Width)  { $dm.dmPelsWidth  = $Width }
if ($Height) { $dm.dmPelsHeight = $Height }
$dm.dmDisplayFrequency = $Hz
# dmFields: PelsWidth | PelsHeight | DisplayFrequency | BitsPerPel
$dm.dmFields = 0x80000 -bor 0x100000 -bor 0x400000 -bor 0x40000

$r = [Disp]::ChangeDisplaySettingsEx($Device, [ref]$dm, [IntPtr]::Zero, [Disp]::CDS_UPDATEREGISTRY, [IntPtr]::Zero)

if ($r -eq [Disp]::DISP_CHANGE_SUCCESSFUL) {
    Write-Output "OK: $oldHz Hz -> $($dm.dmPelsWidth)x$($dm.dmPelsHeight) @ $Hz Hz"
    exit 0
} else {
    Write-Output "failed (code $r): the mode probably does not exist. Run -List to check;"
    Write-Output "23.976 usually needs a custom resolution in NVIDIA Control Panel."
    exit 1
}
