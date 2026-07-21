// SetDisplay.exe <width> <height> <hz> - switch the primary display mode.
// SetDisplay.exe list - print available modes.
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

class SetDisplay
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields;
        public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplaySettingsW(string dev, int modeNum, ref DEVMODE dm);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int ChangeDisplaySettingsW(ref DEVMODE dm, int flags);

    const int ENUM_CURRENT = -1;
    const int CDS_UPDATEREGISTRY = 0x01;
    const int DM_PELSWIDTH = 0x80000, DM_PELSHEIGHT = 0x100000, DM_DISPLAYFREQUENCY = 0x400000;

    static int Main(string[] args)
    {
        var dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));

        if (args.Length == 1 && args[0] == "list")
        {
            for (int i = 0; EnumDisplaySettingsW(null, i, ref dm); i++)
                if (dm.dmPelsWidth >= 3840)
                    Console.WriteLine("{0}x{1}@{2}", dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency);
            return 0;
        }
        if (args.Length != 3)
        {
            Console.WriteLine("usage: SetDisplay <width> <height> <hz> | list");
            return 2;
        }

        int w = int.Parse(args[0]), h = int.Parse(args[1]), hz = int.Parse(args[2]);

        EnumDisplaySettingsW(null, ENUM_CURRENT, ref dm);
        if (dm.dmPelsWidth == w && dm.dmPelsHeight == h && dm.dmDisplayFrequency == hz)
            return 0; // already in this mode

        // look for the exact mode in the list of available ones
        var target = new DEVMODE();
        target.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        bool found = false;
        for (int i = 0; EnumDisplaySettingsW(null, i, ref target); i++)
            if (target.dmPelsWidth == w && target.dmPelsHeight == h && target.dmDisplayFrequency == hz)
            { found = true; break; }

        if (!found)
        {
            MessageBox.Show(string.Format("Mode {0}x{1}@{2} Hz not found among available modes.\nCheck the panel input/cable.", w, h, hz),
                            "SetDisplay", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 3;
        }

        target.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY;
        int r = ChangeDisplaySettingsW(ref target, CDS_UPDATEREGISTRY);
        if (r != 0)
        {
            MessageBox.Show(string.Format("Failed to switch the mode (code {0}).", r),
                            "SetDisplay", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }
}
