Add-Type @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public class GodotCapturer {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr OpenDesktop(string lpszDesktop, uint dwFlags, bool fInherit, uint dwDesiredAccess);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetThreadDesktop(IntPtr hDesktop);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool CloseDesktop(IntPtr hDesktop);

    [DllImport("user32.dll")]
    public static extern bool EnumDesktopWindows(IntPtr hDesktop, EnumDesktopWindowsProc lpfn, IntPtr lParam);
    public delegate bool EnumDesktopWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    [DllImport("gdi32.dll")]
    public static extern bool BitBlt(IntPtr hObject, int nXDest, int nYDest, int nWidth, int nHeight, IntPtr hObjectSource, int nXSrc, int nYSrc, int dwRop);

    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int nIndex);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public static string FocusAndCapture(string outFile) {
        string status = "";
        Thread t = new Thread(() => {
            IntPtr hDesk = OpenDesktop("Default", 0, false, 0x01FF);
            if (hDesk == IntPtr.Zero) {
                status = "Error OpenDesktop";
                return;
            }
            SetThreadDesktop(hDesk);

            IntPtr godotHwnd = IntPtr.Zero;
            EnumDesktopWindows(hDesk, (hwnd, lparam) => {
                StringBuilder sb = new StringBuilder(256);
                GetWindowText(hwnd, sb, 256);
                string title = sb.ToString();
                if (title.Contains("Lindero") && IsWindowVisible(hwnd)) {
                    godotHwnd = hwnd;
                    return false;
                }
                return true;
            }, IntPtr.Zero);

            if (godotHwnd == IntPtr.Zero) {
                status = "Lindero window not found";
                CloseDesktop(hDesk);
                return;
            }

            ShowWindow(godotHwnd, 9); // SW_RESTORE
            SetWindowPos(godotHwnd, (IntPtr)(-1), 0, 0, 1280, 720, 0x0040);
            BringWindowToTop(godotHwnd);
            SetForegroundWindow(godotHwnd);
            Thread.Sleep(800);

            RECT r;
            GetWindowRect(godotHwnd, out r);
            int w = r.Right - r.Left;
            int h = r.Bottom - r.Top;
            if (w <= 0 || h <= 0) {
                status = "Invalid window rect";
                CloseDesktop(hDesk);
                return;
            }

            using (Bitmap bmp = new Bitmap(w, h)) {
                using (Graphics g = Graphics.FromImage(bmp)) {
                    IntPtr dcDesk = GetDC(IntPtr.Zero);
                    IntPtr dcMem = g.GetHdc();
                    BitBlt(dcMem, 0, 0, w, h, dcDesk, r.Left, r.Top, 0x00CC0020);
                    g.ReleaseHdc(dcMem);
                    ReleaseDC(IntPtr.Zero, dcDesk);
                }
                bmp.Save(outFile, ImageFormat.Png);
            }
            CloseDesktop(hDesk);
            status = "Captured " + w + "x" + h;
        });
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join();
        return status;
    }
}
"@ -ReferencedAssemblies System.Drawing

$res = [GodotCapturer]::FocusAndCapture("c:\Users\Usuario\source\JuegosMobile\Lindero\godot_game_window.png")
Write-Output $res
