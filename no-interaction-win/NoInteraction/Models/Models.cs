using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Threading;

namespace NoInteraction.Models
{
    public enum TargetType
    {
        Button,
        Checkbox
    }

    public sealed class ApprovalRule
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public string Keyword { get; set; } = "";
        public bool IsEnabled { get; set; } = true;
        public TargetType TargetType { get; set; }

        public ApprovalRule() { }

        public ApprovalRule(string keyword, TargetType targetType, bool isEnabled = true)
        {
            Keyword = keyword;
            TargetType = targetType;
            IsEnabled = isEnabled;
        }
    }

    public sealed class LogEntry
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public DateTime Timestamp { get; set; } = DateTime.Now;
        public string AppName { get; set; } = "";
        public string ActionTaken { get; set; } = "Auto-Approved";
        public string TargetText { get; set; } = "";
        public string DetectionMethod { get; set; } = "";

        public string FormattedTime => Timestamp.ToString("h:mm:ss tt");
    }

    public sealed class TerminalSession
    {
        public int ProcessId { get; set; }
        public string Title { get; set; } = "";
        public string ProcessName { get; set; } = "Windows Terminal";
        public bool IsAttached { get; set; } = true;
    }

    /// <summary>
    /// Case-insensitive keyword matching with a word-boundary regex fallback, mirroring
    /// the Mac KeywordMatcher so rule behavior is identical across platforms.
    /// </summary>
    public static class ApprovalGeometry
    {
        public static bool IsSecondaryPrimaryPair(double sx, double sy, double sw, double sh,
            double px, double py, double pw, double ph)
        {
            if (sw <= 0 || sh <= 0 || pw <= 0 || ph <= 0) return false;
            var height = Math.Max(sh, ph);
            var gap = px - (sx + sw);
            return gap >= 0 && gap <= height * 6
                && Math.Abs((sy + sh / 2) - (py + ph / 2)) <= height * 0.65;
        }

        public static bool IsDenyAllowPair(double dx, double dy, double dw, double dh,
            double ax, double ay, double aw, double ah)
        {
            return IsSecondaryPrimaryPair(dx, dy, dw, dh, ax, ay, aw, ah);
        }
    }

    public static class KeywordMatcher
    {
        // Chromium includes the visible shortcut in some accessible button names.
        // Strip only a complete modifier/key suffix, never arbitrary trailing prose.
        public static bool MatchesButton(string label, string keyword)
        {
            if (string.IsNullOrWhiteSpace(label) || string.IsNullOrWhiteSpace(keyword)) return false;
            var normalized = Regex.Replace(label.Trim(),
                @"\s+[\(\[]?(?:(?:Alt|Ctrl|Control|Shift|Win)\s*\+\s*)+(?:Enter|Return|Space|[A-Z0-9]|F\d{1,2})[\)\]]?$",
                "", RegexOptions.IgnoreCase);
            return keyword.Trim().Contains(' ')
                ? Matches(normalized, keyword)
                : string.Equals(normalized, keyword.Trim(), StringComparison.OrdinalIgnoreCase);
        }

        private static readonly object CacheLock = new();
        private static readonly Dictionary<string, Regex> RegexCache = new(StringComparer.OrdinalIgnoreCase);

        public static bool Matches(string label, string keyword)
        {
            var kw = keyword?.Trim() ?? "";
            if (string.IsNullOrEmpty(kw) || string.IsNullOrEmpty(label)) return false;

            if (label.IndexOf(kw, StringComparison.OrdinalIgnoreCase) < 0) return false;

            if (string.Equals(label, kw, StringComparison.OrdinalIgnoreCase)) return true;

            Regex regex;
            lock (CacheLock)
            {
                if (!RegexCache.TryGetValue(kw, out regex!))
                {
                    var pattern = $@"\b{Regex.Escape(kw)}\b";
                    regex = new Regex(pattern, RegexOptions.IgnoreCase | RegexOptions.Compiled);
                    RegexCache[kw] = regex;
                }
            }
            return regex.IsMatch(label);
        }

        public static void ClearCache()
        {
            lock (CacheLock)
            {
                RegexCache.Clear();
            }
        }
    }
}
