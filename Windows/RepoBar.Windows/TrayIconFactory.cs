using System.Drawing;
using System.Runtime.InteropServices;

namespace RepoBar.Windows;

internal static class TrayIconFactory
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr handle);

    public static Icon Create(TrayHealth health)
    {
        var fill = health switch
        {
            TrayHealth.Healthy => Color.FromArgb(36, 157, 86),
            TrayHealth.Busy => Color.FromArgb(211, 143, 35),
            TrayHealth.Failing => Color.FromArgb(207, 61, 61),
            _ => Color.FromArgb(96, 101, 109),
        };

        using var bitmap = new Bitmap(32, 32);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.Clear(Color.Transparent);
        graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        using var background = new SolidBrush(fill);
        FillRoundedRectangle(graphics, background, new Rectangle(2, 2, 28, 28), 7);

        using var font = new Font("Segoe UI", 17, FontStyle.Bold, GraphicsUnit.Pixel);
        using var textBrush = new SolidBrush(Color.White);
        var textSize = graphics.MeasureString("R", font);
        graphics.DrawString("R", font, textBrush, (32 - textSize.Width) / 2, (31 - textSize.Height) / 2);

        var handle = bitmap.GetHicon();
        try
        {
            return (Icon)Icon.FromHandle(handle).Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    private static void FillRoundedRectangle(this Graphics graphics, Brush brush, Rectangle bounds, int radius)
    {
        using var path = new System.Drawing.Drawing2D.GraphicsPath();
        var diameter = radius * 2;
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        graphics.FillPath(brush, path);
    }
}
