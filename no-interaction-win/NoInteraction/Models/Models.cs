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
    public static class KeywordMatcher
    {
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
