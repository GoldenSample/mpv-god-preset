// HdrSwitch.exe on|off|toggle|status — HDR (advanced color) основного дисплея.
// status: код возврата 0=выкл, 1=вкл, 2=не поддерживается.
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

class HdrSwitch
{
    [StructLayout(LayoutKind.Sequential)] struct LUID { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)]
    struct PATH_SOURCE { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)]
    struct PATH_TARGET
    {
        public LUID adapterId; public uint id; public uint modeInfoIdx;
        public uint outputTechnology, rotation, scaling, refreshNum, refreshDen, scanLineOrdering;
        public int targetAvailable; public uint statusFlags;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PATH_INFO { public PATH_SOURCE source; public PATH_TARGET target; public uint flags; }
    [StructLayout(LayoutKind.Sequential)]
    struct MODE_INFO
    {
        public uint infoType; public uint id; public LUID adapterId;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 48)] public byte[] u;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct GET_ADV { public uint type; public uint size; public LUID adapterId; public uint id; public uint value; public uint colorEncoding; public uint bits; }
    [StructLayout(LayoutKind.Sequential)]
    struct GET_ADV2 { public uint type; public uint size; public LUID adapterId; public uint id; public uint value; public uint colorEncoding; public uint bits; public uint activeColorMode; }
    [StructLayout(LayoutKind.Sequential)]
    struct SET_ADV { public uint type; public uint size; public LUID adapterId; public uint id; public uint enable; }

    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, ref uint nPath, ref uint nMode);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint nPath, [Out] PATH_INFO[] paths, ref uint nMode, [Out] MODE_INFO[] modes, IntPtr topology);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref GET_ADV p);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref GET_ADV2 p);
    [DllImport("user32.dll")] static extern int DisplayConfigSetDeviceInfo(ref SET_ADV p);

    // 1=вкл, 0=выкл, -1=не читается. Сначала новый API (activeColorMode: 2=HDR),
    // фолбэк на легаси-бит advancedColorEnabled.
    static int ReadHdr(LUID adapter, uint id)
    {
        var g2 = new GET_ADV2();
        g2.type = 15; // GET_ADVANCED_COLOR_INFO_2
        g2.size = (uint)Marshal.SizeOf(typeof(GET_ADV2));
        g2.adapterId = adapter; g2.id = id;
        if (DisplayConfigGetDeviceInfo(ref g2) == 0)
            return g2.activeColorMode == 2 ? 1 : 0;
        var g = new GET_ADV();
        g.type = 9;
        g.size = (uint)Marshal.SizeOf(typeof(GET_ADV));
        g.adapterId = adapter; g.id = id;
        if (DisplayConfigGetDeviceInfo(ref g) == 0 && (g.value & 1) != 0)
            return (g.value & 2) != 0 ? 1 : 0;
        return -1;
    }

    const uint QDC_ONLY_ACTIVE_PATHS = 2;

    // HDR по HDMI применяется не мгновенно: панель пересинхронизируется
    // секунды. Опрашиваем состояние до таймаута вместо мгновенной проверки.
    static bool WaitState(LUID adapter, uint id, bool want, int timeoutMs)
    {
        for (int t = 0; t < timeoutMs; t += 250)
        {
            if (ReadHdr(adapter, id) == (want ? 1 : 0)) return true;
            System.Threading.Thread.Sleep(250);
        }
        return ReadHdr(adapter, id) == (want ? 1 : 0);
    }

    static int Main(string[] args)
    {
        string cmd = args.Length > 0 ? args[0] : "toggle";

        uint nPath = 0, nMode = 0;
        GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, ref nPath, ref nMode);
        var paths = new PATH_INFO[nPath];
        var modes = new MODE_INFO[nMode];
        if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref nPath, paths, ref nMode, modes, IntPtr.Zero) != 0)
        { Fail("QueryDisplayConfig не ответил."); return 2; }

        int result = 2;
        int switched = 0, failed = 0;
        for (int i = 0; i < nPath; i++)
        {
            int state = ReadHdr(paths[i].target.adapterId, paths[i].target.id);
            if (state < 0) continue;
            bool enabled = state == 1;

            if (cmd == "status") { result = state; continue; }

            bool want = cmd == "on" ? true : cmd == "off" ? false : !enabled;
            if (want == enabled) { result = state; continue; }

            // Windows 11 24H2+: тип SET_HDR_STATE (16); легаси (10) как фолбэк
            var s = new SET_ADV();
            s.type = 16;
            s.size = (uint)Marshal.SizeOf(typeof(SET_ADV));
            s.adapterId = paths[i].target.adapterId;
            s.id = paths[i].target.id;
            s.enable = want ? 1u : 0u;
            DisplayConfigSetDeviceInfo(ref s);
            bool ok = WaitState(paths[i].target.adapterId, paths[i].target.id, want, 4000);

            if (!ok)
            {
                s.type = 10;
                DisplayConfigSetDeviceInfo(ref s);
                ok = WaitState(paths[i].target.adapterId, paths[i].target.id, want, 3000);
            }

            if (ok) { switched++; result = want ? 1 : 0; }
            else failed++;
        }

        if (cmd != "status" && switched == 0 && failed > 0)
        {
            Fail("HDR не переключился ни на одном дисплее (пробовал " + failed + ").");
            return 2;
        }
        if (result == 2 && cmd != "status")
            Fail("HDR не поддерживается активным дисплеем (или выключен в Windows).");
        return result;
    }

    static void Fail(string msg)
    {
        MessageBox.Show(msg, "HdrSwitch", MessageBoxButtons.OK, MessageBoxIcon.Warning);
    }
}
