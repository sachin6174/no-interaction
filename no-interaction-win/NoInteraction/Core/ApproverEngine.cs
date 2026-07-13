using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Windows;
using NoInteraction.Models;

namespace NoInteraction.Core
{
    /// <summary>
    /// Windows port of the Mac build's ApproverEngine: owns settings, rules, the activity
    /// log, and the periodic scan loop. Intentionally does not include the Mac app's
    /// Prompt Queue / Loop Mode auto-paste feature.
    /// </summary>
    public sealed class ApproverEngine : INotifyPropertyChanged
    {
        public static readonly ApproverEngine Shared = new();

        public event PropertyChangedEventHandler? PropertyChanged;
        private void Raise([CallerMemberName] string? name = null) =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

        private readonly SettingsStore _settings;

        private bool _isEnabled;
        public bool IsEnabled
        {
            get => _isEnabled;
            set { if (_isEnabled == value) return; _isEnabled = value; _settings.IsEnabled = value; _settings.Save(); Raise(); }
        }

        // Windows has no OS-level "grant accessibility" gate for same-privilege automation,
        // so this always reports true; kept for structural parity with the Mac dashboard.
        public bool IsAccessibilityGranted => true;

        private int _totalApprovalsCount;
        public int TotalApprovalsCount
        {
            get => _totalApprovalsCount;
            private set { _totalApprovalsCount = value; _settings.TotalApprovalsCount = value; _settings.Save(); Raise(); }
        }

        private bool _soundEnabled;
        public bool SoundEnabled
        {
            get => _soundEnabled;
            set { if (_soundEnabled == value) return; _soundEnabled = value; _settings.SoundEnabled = value; _settings.Save(); Raise(); }
        }

        public ObservableCollection<LogEntry> Logs { get; } = new();
        public ObservableCollection<ApprovalRule> ButtonRules { get; } = new();
        public ObservableCollection<ApprovalRule> CheckboxRules { get; } = new();

        private static readonly string[] DefaultButtons =
        {
            "Submit", "Allow", "Yes, allow", "Yes, and always", "Approve",
            "Yes", "Confirm", "Proceed", "Accept", "Continue", "OK"
        };
        private static readonly string[] DefaultCheckboxes =
        {
            "Remember", "Always", "Trust", "Don't ask", "Don't show"
        };

        private readonly System.Threading.Timer _timer;
        private DateTime _lastActionTime = DateTime.MinValue;
        private readonly TimeSpan _cooldown = TimeSpan.FromSeconds(1.2);
        private volatile bool _ocrScanInFlight;
        private readonly object _scanLock = new();

        private ApproverEngine()
        {
            _settings = SettingsStore.Load();

            _isEnabled = _settings.IsEnabled;
            _soundEnabled = _settings.SoundEnabled;
            _totalApprovalsCount = _settings.TotalApprovalsCount;

            var buttons = _settings.ButtonRules.Count > 0
                ? _settings.ButtonRules
                : DefaultButtons.Select(k => new ApprovalRule(k, TargetType.Button)).ToList();
            buttons.RemoveAll(r => string.Equals(r.Keyword, "Run", StringComparison.OrdinalIgnoreCase)
                                 || string.Equals(r.Keyword, "Execute", StringComparison.OrdinalIgnoreCase));
            foreach (var r in buttons) ButtonRules.Add(r);

            var checkboxes = _settings.CheckboxRules.Count > 0
                ? _settings.CheckboxRules
                : DefaultCheckboxes.Select(k => new ApprovalRule(k, TargetType.Checkbox)).ToList();
            foreach (var r in checkboxes) CheckboxRules.Add(r);

            ButtonRules.CollectionChanged += (_, _) => SaveRules();
            CheckboxRules.CollectionChanged += (_, _) => SaveRules();

            _timer = new System.Threading.Timer(_ => ScheduleScan(), null, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(3));
        }

        private void SaveRules()
        {
            _settings.ButtonRules = ButtonRules.ToList();
            _settings.CheckboxRules = CheckboxRules.ToList();
            _settings.Save();
        }

        // MARK: Scan loop

        private void ScheduleScan()
        {
            if (!IsEnabled) return;
            if (DateTime.Now - _lastActionTime < _cooldown) return;

            List<string> buttons, checkboxes;
            lock (_scanLock)
            {
                buttons = ButtonRules.Where(r => r.IsEnabled).Select(r => r.Keyword).ToList();
                checkboxes = CheckboxRules.Where(r => r.IsEnabled).Select(r => r.Keyword).ToList();
            }
            if (buttons.Count == 0) return;

            var targetApps = AppObserver.Shared.FindTargetApplications();
            if (targetApps.Count == 0) return;

            foreach (var app in targetApps)
            {
                string appName;
                try { appName = string.IsNullOrEmpty(app.MainWindowTitle) ? app.ProcessName : app.MainWindowTitle; }
                catch { appName = "Target App"; }

                UiaInspector.InspectionResult? result;
                try { result = UiaInspector.Shared.InspectAndAutoApprove(app, buttons, checkboxes); }
                catch { result = null; }

                if (result != null)
                {
                    _lastActionTime = DateTime.Now;
                    if (result.Action == "Fallback Click Needed" && result.Position.HasValue)
                    {
                        ClickAutomation.Shared.PerformClick(result.Position.Value, () =>
                            Record(appName, result.ElementText, "UIA + Click"));
                    }
                    else
                    {
                        Record(appName, result.ElementText, result.Action);
                    }
                    return; // matches Mac behavior: stop after the first successful action this tick
                }
            }

            // Pass 2: OCR fallback if nothing was found via UI Automation
            if (_ocrScanInFlight) return;
            foreach (var app in targetApps)
            {
                var bounds = AppObserver.Shared.GetWindowBounds(app);
                if (bounds == null) continue;

                _ocrScanInFlight = true;
                var capturedApp = app;
                string capturedAppName = appName;

                _ = RunOcrPassAsync(bounds.Value, buttons, capturedApp, capturedAppName);
                break;
            }
        }

        private async System.Threading.Tasks.Task RunOcrPassAsync(Rect bounds, List<string> buttons, System.Diagnostics.Process app, string appName)
        {
            try
            {
                var (point, text) = await OcrScanner.Shared.ScanRegionForKeywordsAsync(bounds, buttons);
                if (point == null || text == null) return;
                if (DateTime.Now - _lastActionTime < _cooldown) return;

                _lastActionTime = DateTime.Now;
                ClickAutomation.Shared.PerformClick(point.Value, () => Record(appName, text, "OCR"));
            }
            finally
            {
                _ocrScanInFlight = false;
            }
        }

        // MARK: Logging & audio feedback

        private void Record(string appName, string text, string method)
        {
            Application.Current?.Dispatcher.Invoke(() =>
            {
                TotalApprovalsCount += 1;
                var entry = new LogEntry
                {
                    AppName = appName,
                    ActionTaken = "Auto-Approved",
                    TargetText = text,
                    DetectionMethod = method
                };
                Logs.Insert(0, entry);
                while (Logs.Count > 200) Logs.RemoveAt(Logs.Count - 1);

                if (SoundEnabled)
                {
                    try { System.Media.SystemSounds.Asterisk.Play(); } catch { }
                }
            });
        }

        // MARK: Rule management

        public void AddRule(string keyword, TargetType targetType)
        {
            var kw = keyword.Trim();
            if (string.IsNullOrEmpty(kw)) return;
            var collection = targetType == TargetType.Button ? ButtonRules : CheckboxRules;
            if (collection.Any(r => string.Equals(r.Keyword, kw, StringComparison.OrdinalIgnoreCase))) return;
            collection.Add(new ApprovalRule(kw, targetType));
        }

        public void RemoveRule(Guid id, TargetType targetType)
        {
            var collection = targetType == TargetType.Button ? ButtonRules : CheckboxRules;
            var rule = collection.FirstOrDefault(r => r.Id == id);
            if (rule != null) collection.Remove(rule);
        }

        public void ToggleRule(Guid id, TargetType targetType)
        {
            var collection = targetType == TargetType.Button ? ButtonRules : CheckboxRules;
            var rule = collection.FirstOrDefault(r => r.Id == id);
            if (rule == null) return;
            rule.IsEnabled = !rule.IsEnabled;
            SaveRules();
            // Force UI refresh since mutating a property on an item doesn't raise CollectionChanged.
            var idx = collection.IndexOf(rule);
            collection.RemoveAt(idx);
            collection.Insert(idx, rule);
        }

        public void ResetRulesToDefault()
        {
            ButtonRules.Clear();
            foreach (var k in DefaultButtons) ButtonRules.Add(new ApprovalRule(k, TargetType.Button));
            CheckboxRules.Clear();
            foreach (var k in DefaultCheckboxes) CheckboxRules.Add(new ApprovalRule(k, TargetType.Checkbox));
        }
    }
}
