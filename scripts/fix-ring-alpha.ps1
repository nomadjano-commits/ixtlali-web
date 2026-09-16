Add-Type -AssemblyName System.Drawing

$src = "C:\Users\NomadJano\Downloads\exacto_160_4000_1500.png"
$dst = "C:\Users\NomadJano\Desktop\Proyectos Web\Ix'tlali ManuMX\Ix'tlali-web\assets\ring-pattern.png"
$erosion = 0   # px to erode from each edge of the line, at native source resolution

$csharp = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class RingProcessor {
    public static void Process(string src, string dst, int erosion) {
        Bitmap bmp = (Bitmap)Bitmap.FromFile(src);
        int w = bmp.Width, h = bmp.Height;
        Rectangle rect = new Rectangle(0, 0, w, h);
        BitmapData dataIn = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int stride = dataIn.Stride;
        byte[] bytes = new byte[stride * h];
        Marshal.Copy(dataIn.Scan0, bytes, 0, bytes.Length);
        bmp.UnlockBits(dataIn);

        // 1. binary "is dark line" mask: use real alpha if the source has any,
        //    else fall back to luminance-keying against a flattened white/light bg
        bool hasAlpha = false;
        for (int y = 0; y < h && !hasAlpha; y += 7) {
            for (int x = 0; x < w; x += 7) {
                if (bytes[y * stride + x * 4 + 3] < 250) { hasAlpha = true; break; }
            }
        }

        bool[,] dark = new bool[w, h];
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int i = y * stride + x * 4;
                if (hasAlpha) {
                    dark[x, y] = bytes[i + 3] > 128;
                } else {
                    int b = bytes[i], g = bytes[i + 1], r = bytes[i + 2];
                    double lum = (r + g + b) / 3.0;
                    dark[x, y] = lum < 140;
                }
            }
        }

        // 2. distance-to-background transform (Manhattan, 2-pass chamfer) for dark pixels
        int[,] dist = new int[w, h];
        int BIG = 1 << 20;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                dist[x, y] = dark[x, y] ? BIG : 0;

        // forward pass
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                if (!dark[x, y]) continue;
                int best = dist[x, y];
                if (x > 0) best = Math.Min(best, dist[x - 1, y] + 1);
                if (y > 0) best = Math.Min(best, dist[x, y - 1] + 1);
                dist[x, y] = best;
            }
        }
        // backward pass
        for (int y = h - 1; y >= 0; y--) {
            for (int x = w - 1; x >= 0; x--) {
                if (!dark[x, y]) continue;
                int best = dist[x, y];
                if (x < w - 1) best = Math.Min(best, dist[x + 1, y] + 1);
                if (y < h - 1) best = Math.Min(best, dist[x, y + 1] + 1);
                dist[x, y] = best;
            }
        }

        // 3. gold gradient stops
        double[] goldLight = { 246, 221, 140 };
        double[] gold = { 212, 175, 55 };
        double[] goldDark = { 138, 106, 31 };

        byte[] outBytes = new byte[stride * h];
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int d = dist[x, y];
                double a = (d > erosion) ? 255 : 0;

                double t = ((x / (double)w) + (y / (double)h)) / 2.0;
                double cr, cg, cb;
                if (t <= 0.55) {
                    double f = t / 0.55;
                    cr = goldLight[0] + (gold[0] - goldLight[0]) * f;
                    cg = goldLight[1] + (gold[1] - goldLight[1]) * f;
                    cb = goldLight[2] + (gold[2] - goldLight[2]) * f;
                } else {
                    double f = (t - 0.55) / 0.45;
                    if (f > 1) f = 1;
                    cr = gold[0] + (goldDark[0] - gold[0]) * f;
                    cg = gold[1] + (goldDark[1] - gold[1]) * f;
                    cb = gold[2] + (goldDark[2] - gold[2]) * f;
                }

                int o = y * stride + x * 4;
                outBytes[o] = (byte)cb;
                outBytes[o + 1] = (byte)cg;
                outBytes[o + 2] = (byte)cr;
                outBytes[o + 3] = (byte)a;
            }
        }

        Bitmap outBmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        BitmapData dataOut = outBmp.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(outBytes, 0, dataOut.Scan0, outBytes.Length);
        outBmp.UnlockBits(dataOut);
        outBmp.Save(dst, ImageFormat.Png);
    }
}
'@

Add-Type -TypeDefinition $csharp -ReferencedAssemblies System.Drawing

[RingProcessor]::Process($src, $dst, $erosion)
Write-Output "Saved: $dst (erosion=$erosion)"
