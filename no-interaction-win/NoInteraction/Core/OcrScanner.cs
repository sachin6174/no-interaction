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
        private DateTime _lastImageTime;
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
                if (_lastImageHash == hash && DateTime.UtcNow - _lastImageTime < TimeSpan.FromSeconds(2))
                {
                    return (null, null); // Skip OCR scan if the screen region has not changed
                }
                _lastImageHash = hash;
                _lastImageTime = DateTime.UtcNow;
            }

            return await ScanBitmapAsync(bitmap, targetRect, buttonKeywords);
        }

        internal async Task<(Point? point, string? text)> ScanBitmapAsync(Bitmap bitmap, Rect targetRect,
            System.Collections.Generic.List<string> buttonKeywords)
        {
            var engine = OcrEngine.TryCreateFromUserProfileLanguages();
            if (engine == null) return (null, null);

            SoftwareBitmap? softwareBitmap = null;
            try
            {
                // Small approval labels can disappear entirely at native resolution.
                // Upscale for recognition and map every result back to screen pixels.
                double scale = Math.Min(4.0, (double)OcrEngine.MaxImageDimension / Math.Max(bitmap.Width, bitmap.Height));
                using var enlarged = new Bitmap(Math.Max(1, (int)(bitmap.Width * scale)), Math.Max(1, (int)(bitmap.Height * scale)));
                double scaleX = (double)enlarged.Width / bitmap.Width;
                double scaleY = (double)enlarged.Height / bitmap.Height;
                var lines = new System.Collections.Generic.List<OcrLine>();
                for (int pass = 0; pass < 2; pass++)
                {
                    using (var graphics = Graphics.FromImage(enlarged))
                    {
                        graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                        using var attributes = new ImageAttributes();
                        if (pass == 1)
                        {
                            // Isolate bright text from blue button backgrounds. Retain the
                            // normal pass too, since dim Deny labels need their original contrast.
                            attributes.SetColorMatrix(new ColorMatrix(new[]
                            {
                        new float[] { -1, -1, -1, 0, 0 },
                        new float[] { 0, 0, 0, 0, 0 },
                        new float[] { 0, 0, 0, 0, 0 },
                        new float[] { 0, 0, 0, 1, 0 },
                        new float[] { 1, 1, 1, 0, 1 }
                    }));
                            attributes.SetThreshold(.35f);
                        }
                        graphics.DrawImage(bitmap, new Rectangle(0, 0, enlarged.Width, enlarged.Height),
                            0, 0, bitmap.Width, bitmap.Height, GraphicsUnit.Pixel, attributes);
                    }
                    using var memStream = new MemoryStream();
                    enlarged.Save(memStream, ImageFormat.Png);
                    memStream.Position = 0;

                    using var raStream = memStream.AsRandomAccessStream();

                    var decoder = await BitmapDecoder.CreateAsync(raStream);
                    softwareBitmap?.Dispose();
                    softwareBitmap = await decoder.GetSoftwareBitmapAsync();

                    var result = await engine.RecognizeAsync(softwareBitmap);
                    lines.AddRange(result.Lines);
                }

                // Single-word primary actions are safe only when paired with the expected
                // secondary action on the same row. This covers Deny + Allow and
                // Skip + Submit while avoiding unrelated Allow/Submit text in page content.
                var allWords = lines.SelectMany(l => l.Words).ToList();
                foreach (var primaryName in new[] { "Allow", "Submit" })
                {
                    if (!buttonKeywords.Any(k => string.Equals(k.Trim(), primaryName, StringComparison.OrdinalIgnoreCase))) continue;
                    var secondaryName = primaryName == "Allow" ? "Deny" : "Skip";
                    foreach (var primary in allWords.Where(w => string.Equals(w.Text, primaryName, StringComparison.OrdinalIgnoreCase)))
                    {
                        var p = primary.BoundingRect;
                        var paired = allWords.Any(w => string.Equals(w.Text, secondaryName, StringComparison.OrdinalIgnoreCase)
                            && ApprovalGeometry.IsSecondaryPrimaryPair(w.BoundingRect.X, w.BoundingRect.Y,
                                w.BoundingRect.Width, w.BoundingRect.Height, p.X, p.Y, p.Width, p.Height));
                        if (paired)
                            return (new Point(targetRect.X + (p.X + p.Width / 2) / scaleX,
                                targetRect.Y + (p.Y + p.Height / 2) / scaleY), primaryName);
                    }
                }

                foreach (var line in lines)
                {
                    var text = line.Text.Trim();
                    if (string.IsNullOrEmpty(text) || text.Length > 40) continue;

                    // OCR has no way to verify an element is actually clickable — unlike UI
                    // Automation it can't check for an Invoke pattern, it just reads pixels.
                    // A generic single word ("Run", "OK", "Yes", "Continue", ...) shows up
                    // constantly in ordinary UI chrome (menu bars, toolbars, "Continue
                    // reading" links, ...), so only match on distinctive multi-word phrases
                    // here ("Always Allow", "Run Command", ...) that are very unlikely to
                    // appear anywhere except a real approval dialog.
                    var isMatch = buttonKeywords.Any(k => k.Trim().Contains(' ') && KeywordMatcher.Matches(text, k));
                    if (!isMatch) continue;

                    var words = line.Words;
                    if (words.Count == 0) continue;

                    double minX = words.Min(w => w.BoundingRect.X);
                    double maxX = words.Max(w => w.BoundingRect.X + w.BoundingRect.Width);
                    double minY = words.Min(w => w.BoundingRect.Y);
                    double maxY = words.Max(w => w.BoundingRect.Y + w.BoundingRect.Height);

                    var screenX = targetRect.X + (minX + maxX) / (2.0 * scaleX);
                    var screenY = targetRect.Y + (minY + maxY) / (2.0 * scaleY);

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

        /// <summary>Real prompts in these agent chat panels render somewhere in the right-side
        /// chat panel — not necessarily pinned to the bottom edge, since it's a scrolling
        /// conversation — but never in the menu bar or a left-hand sidebar. Matches
        /// UiaInspector's PromptRegionOf so both detection paths agree on where a prompt can
        /// legitimately be, and it's cheaper to capture/OCR than the full window.</summary>
        private Rect ButtonStripRect(Rect bounds)
        {
            var regionWidth = bounds.Width * 0.55;
            var regionHeight = bounds.Height * 0.8;
            return new Rect(bounds.Right - regionWidth, bounds.Bottom - regionHeight, regionWidth, regionHeight);
        }

        private Bitmap? CaptureScreenRegion(Rect rect)
        {
            Bitmap? bmp = null;
            try
            {
                bmp = new Bitmap((int)rect.Width, (int)rect.Height);
                using var g = Graphics.FromImage(bmp);
                g.CopyFromScreen((int)rect.X, (int)rect.Y, 0, 0, bmp.Size);
                return bmp;
            }
            catch
            {
                bmp?.Dispose();
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
