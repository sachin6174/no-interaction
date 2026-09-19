using System;
using System.Collections.Generic;
using System.Drawing;
using System.Threading.Tasks;
using NoInteraction.Core;
using NoInteraction.Models;

internal static class Program
{
    private static void Check(bool value, string name)
    {
        if (!value) throw new Exception("FAIL: " + name);
        Console.WriteLine("PASS: " + name);
    }

    private static async Task Main(string[] args)
    {
        foreach (var label in new[] { "Allow", "Allow Alt+Enter", "Allow  Alt + Enter", "Allow (Ctrl+Shift+Enter)", "allow\nAlt+Enter" })
            Check(KeywordMatcher.MatchesButton(label, "Allow"), label.Replace('\n', ' '));
        foreach (var label in new[] { "Disallow", "Always Allow", "Allow all websites", "Do not Allow", "Click Allow Alt+Enter", "Allow Alt+Enter arbitrary text" })
            Check(!KeywordMatcher.MatchesButton(label, "Allow"), "reject " + label);
        Check(!KeywordMatcher.MatchesButton("Quick Open", "Open"), "reject toolbar command");
        Check(!KeywordMatcher.MatchesButton("Allow", ""), "reject empty rule");
        Check(KeywordMatcher.MatchesButton("Always Allow Alt+Enter", "Always Allow"), "multiword rule");
        Check(ApprovalGeometry.IsDenyAllowPair(866, 186, 25, 11, 913, 186, 27, 11), "screenshot button geometry");
        Check(!ApprovalGeometry.IsDenyAllowPair(866, 146, 25, 11, 913, 186, 27, 11), "reject different rows");
        Check(!ApprovalGeometry.IsDenyAllowPair(66, 186, 25, 11, 913, 186, 27, 11), "reject distant text");
        Check(!ApprovalGeometry.IsDenyAllowPair(966, 186, 25, 11, 913, 186, 27, 11), "reject reversed pair");
        
        {
            using var bitmap = new Bitmap(args.Length > 0 ? args[0]
                : System.IO.Path.Combine(AppContext.BaseDirectory, "Fixtures", "allow-prompt.png"));
            var crop = new Rectangle((int)(bitmap.Width * .45), (int)(bitmap.Height * .2), (int)(bitmap.Width * .55), (int)(bitmap.Height * .8));
            using var panel = bitmap.Clone(crop, bitmap.PixelFormat);
            var region = new System.Windows.Rect(crop.X, crop.Y, crop.Width, crop.Height);
            var result = await OcrScanner.Shared.ScanBitmapAsync(panel, region, new List<string> { "Allow" });
            Check(result.text == "Allow" && result.point.HasValue
                && new System.Windows.Rect(903, 179, 99, 24).Contains(result.point.Value), "attached screenshot OCR targets Allow button");
            var disabled = await OcrScanner.Shared.ScanBitmapAsync(panel, region, new List<string>());
            Check(disabled.point == null, "disabled Allow rule is respected");
            var full = await OcrScanner.Shared.ScanBitmapAsync(bitmap,
                new System.Windows.Rect(0, 0, bitmap.Width, bitmap.Height), new List<string> { "Allow" });
            Check(full.point.HasValue && new System.Windows.Rect(903, 179, 99, 24).Contains(full.point.Value),
                "full screenshot OCR coordinates");
            using (var graphics = Graphics.FromImage(panel))
                graphics.FillRectangle(Brushes.Black, 854 - crop.X, 179 - crop.Y, 45, 24);
            var unpaired = await OcrScanner.Shared.ScanBitmapAsync(panel, region, new List<string> { "Allow" });
            Check(unpaired.point == null, "OCR requires adjacent Deny");
        }

        {
            using var bitmap = new Bitmap(System.IO.Path.Combine(AppContext.BaseDirectory, "Fixtures", "submit-prompt.png"));
            var region = new System.Windows.Rect(0, 0, bitmap.Width, bitmap.Height);
            var result = await OcrScanner.Shared.ScanBitmapAsync(bitmap, region, new List<string> { "Submit" });
            Check(result.text == "Submit" && result.point.HasValue
                && new System.Windows.Rect(608, 245, 74, 33).Contains(result.point.Value),
                "attached screenshot OCR targets Submit button");
            var disabled = await OcrScanner.Shared.ScanBitmapAsync(bitmap, region, new List<string>());
            Check(disabled.point == null, "disabled Submit rule is respected");
            using (var graphics = Graphics.FromImage(bitmap))
                graphics.FillRectangle(Brushes.Black, 555, 245, 50, 33);
            var unpaired = await OcrScanner.Shared.ScanBitmapAsync(bitmap, region, new List<string> { "Submit" });
            Check(unpaired.point == null, "OCR requires adjacent Skip");
        }
    }
}
