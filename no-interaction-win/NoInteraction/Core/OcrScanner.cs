using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading.Tasks;
using System.Windows;
using NoInteraction.Models;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Point = System.Windows.Point;
using Rect = System.Windows.Rect;

namespace NoInteraction.Core
{
    /// <summary>
    /// Windows.Media.Ocr fallback scanner — the Windows equivalent of the Mac build's
    /// Vision-based VisionOCRScanner. Used only when UI Automation can't see a button
    /// (e.g. it's rendered inside a canvas/custom-drawn surface).
    /// </summary>
    public sealed class OcrScanner
    {
        public static readonly OcrScanner Shared = new();
        private string? _lastImageHash;
        private readonly object _hashLock = new();

        public async Task<(Point? point, string? text)> ScanRegionForKeywordsAsync(Rect windowBounds, System.Collections.Generic.List<string> buttonKeywords)
        {
            var targetRect = ButtonStripRect(windowBounds);
            if (targetRect.Width <= 0 || targetRect.Height <= 0) return (null, null);

            using var bitmap = CaptureScreenRegion(targetRect);
            if (bitmap == null) return (null, null);

            var hash = ComputeBitmapHash(bitmap);
            lock (_hashLock)
            {
                if (_lastImageHash == hash)
                {
                    return (null, null); // Skip OCR scan if the screen region has not changed
                }
                _lastImageHash = hash;
            }

            var engine = OcrEngine.TryCreateFromUserProfileLanguages();
            if (engine == null) return (null, null);

            SoftwareBitmap? softwareBitmap = null;
            try
            {
                using var memStream = new MemoryStream();
                bitmap.Save(memStream, ImageFormat.Png);
                memStream.Position = 0;

                using var raStream = memStream.AsRandomAccessStream();

                var decoder = await BitmapDecoder.CreateAsync(raStream);
                softwareBitmap = await decoder.GetSoftwareBitmapAsync();

                var result = await engine.RecognizeAsync(softwareBitmap);

                foreach (var line in result.Lines)
                {
                    var text = line.Text.Trim();
                    if (string.IsNullOrEmpty(text) || text.Length > 40) continue;

                    var isMatch = buttonKeywords.Any(k => KeywordMatcher.Matches(text, k));
                    if (!isMatch) continue;

                    var words = line.Words;
                    if (words.Count == 0) continue;

                    double minX = words.Min(w => w.BoundingRect.X);
                    double maxX = words.Max(w => w.BoundingRect.X + w.BoundingRect.Width);
                    double minY = words.Min(w => w.BoundingRect.Y);
                    double maxY = words.Max(w => w.BoundingRect.Y + w.BoundingRect.Height);

                    var screenX = targetRect.X + (minX + maxX) / 2.0;
                    var screenY = targetRect.Y + (minY + maxY) / 2.0;

                    Console.WriteLine($"[OcrScanner] Found '{text}' at ({(int)screenX}, {(int)screenY})");
                    return (new Point(screenX, screenY), text);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[OcrScanner] OCR failed: {ex.Message}");
            }
            finally
            {
                softwareBitmap?.Dispose();
            }
            return (null, null);
        }

        /// <summary>Returns only the bottom ~30% of the window — where approval buttons live.</summary>
        private Rect ButtonStripRect(Rect bounds)
        {
            var stripH = Math.Max(80, bounds.Height * 0.30);
            return new Rect(bounds.X, bounds.Bottom - stripH, bounds.Width, stripH);
        }

        private Bitmap? CaptureScreenRegion(Rect rect)
        {
            try
            {
                var bmp = new Bitmap((int)rect.Width, (int)rect.Height);
                using var g = Graphics.FromImage(bmp);
                g.CopyFromScreen((int)rect.X, (int)rect.Y, 0, 0, bmp.Size);
                return bmp;
            }
            catch
            {
                return null;
            }
        }

        private string ComputeBitmapHash(Bitmap bmp)
        {
            var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
            var bmpData = bmp.LockBits(rect, ImageLockMode.ReadOnly, bmp.PixelFormat);
            try
            {
                int bytes = Math.Abs(bmpData.Stride) * bmp.Height;
                byte[] rgbValues = new byte[bytes];
                System.Runtime.InteropServices.Marshal.Copy(bmpData.Scan0, rgbValues, 0, bytes);
                using var md5 = System.Security.Cryptography.MD5.Create();
                var hashBytes = md5.ComputeHash(rgbValues);
                return BitConverter.ToString(hashBytes).Replace("-", "").ToLowerInvariant();
            }
            finally
            {
                bmp.UnlockBits(bmpData);
            }
        }
    }
}
