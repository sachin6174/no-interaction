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
    public sealed class ApproverEngine : INotifyPropertyChanged, IDisposable
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

        public static readonly string DefaultPrompt = @"Perform a complete, exhaustive, and uncompromising security, architecture, performance, and UI/UX audit of this entire codebase. Analyze every single line of code with extreme depth and rigor.

Your objective is to optimize this application to the absolute highest tier of software quality in existence. Follow these strict directives:
1. BUG DETECTION & RESOLUTION: Scan for any logical bugs, concurrency race conditions, memory leaks, performance bottlenecks, edge-case crashes, and API misuses. Resolve them immediately with clean, production-ready, and robust code.
2. CODE OPTIMIZATION & REFACTORING: Optimize compile times, memory footprints, and CPU utilization. Eliminate redundant loops and heavy UI renderings. Ensure optimal concurrency paradigms.
3. UI/UX REFINEMENT: Review all layouts, fonts, spacing, color contrasts, transitions, and hover animations. Upgrade the visual design system to feel premium, modern, and state-of-the-art.
4. EDGE CASES & ROBUSTNESS: Ensure perfect error handling, validation, and defensive coding against unexpected window hierarchies or missing permissions.
5. DEEP SEARCH: Use the internet, latest documentation, SDK guidelines, and the full extent of your cognitive capacity. Do not stop until this codebase is completely flawless.";

        public ObservableCollection<string> PromptQueue { get; } = new();

        private int _currentPromptIndex;
        public int CurrentPromptIndex
        {
            get => _currentPromptIndex;
            set { if (_currentPromptIndex == value) return; _currentPromptIndex = value; _settings.CurrentPromptIndex = value; _settings.Save(); Raise(); }
        }

        private bool _isPromptQueueActive = true;
        public bool IsPromptQueueActive
        {
            get => _isPromptQueueActive;
            set { if (_isPromptQueueActive == value) return; _isPromptQueueActive = value; _settings.IsPromptQueueActive = value; _settings.Save(); Raise(); }
        }

        private bool _loopModeEnabled;
        public bool LoopModeEnabled
        {
            get => _loopModeEnabled;
            set { if (_loopModeEnabled == value) return; _loopModeEnabled = value; _settings.LoopModeEnabled = value; _settings.Save(); Raise(); }
        }

        private int _loopModeLimit = 10;
        public int LoopModeLimit
        {
            get => _loopModeLimit;
            set { if (_loopModeLimit == value) return; _loopModeLimit = value; _settings.LoopModeLimit = value; _settings.Save(); Raise(); }
        }

        private int _loopModeCounter;
        public int LoopModeCounter
        {
            get => _loopModeCounter;
            set { if (_loopModeCounter == value) return; _loopModeCounter = value; _settings.LoopModeCounter = value; _settings.Save(); Raise(); }
        }

        private bool _terminalMonitoringEnabled = true;
        public bool TerminalMonitoringEnabled
        {
            get => _terminalMonitoringEnabled;
            set { if (_terminalMonitoringEnabled == value) return; _terminalMonitoringEnabled = value; Raise(); }
        }

        public ObservableCollection<TerminalSession> TerminalSessions { get; } = new();

        private static readonly string[] DefaultButtons =
        {
            "Submit", "Allow", "Always Allow", "Allow All", "Yes, allow", "Yes, and always", "Approve",
            "Yes", "Confirm", "Proceed", "Accept", "Continue", "OK", "Trust", "Got it", "Install", "Open",
            "Run Command", "Run", "Execute", "Always Allow Command", "Always Run", "Run Tool", "Allow Tool"
        };
        private static readonly string[] DefaultCheckboxes =
        {
            "Remember", "Always", "Trust", "Don't ask", "Don't show", "Remember my choice", "Do not ask again"
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
            foreach (var r in buttons) ButtonRules.Add(r);

            var checkboxes = _settings.CheckboxRules.Count > 0
                ? _settings.CheckboxRules
                : DefaultCheckboxes.Select(k => new ApprovalRule(k, TargetType.Checkbox)).ToList();
            foreach (var r in checkboxes) CheckboxRules.Add(r);

            if (_settings.PromptQueue.Count > 0)
            {
                foreach (var pq in _settings.PromptQueue) PromptQueue.Add(pq);
            }
            else
            {
                PromptQueue.Add(DefaultPrompt);
            }
            _currentPromptIndex = _settings.CurrentPromptIndex;
            _isPromptQueueActive = _settings.IsPromptQueueActive;
            _loopModeEnabled = _settings.LoopModeEnabled;
            _loopModeLimit = _settings.LoopModeLimit;
            _loopModeCounter = _settings.LoopModeCounter;

            ButtonRules.CollectionChanged += (_, _) => SaveRules();
            CheckboxRules.CollectionChanged += (_, _) => SaveRules();
            PromptQueue.CollectionChanged += (_, _) => SavePromptQueue();

            _timer = new System.Threading.Timer(_ => ScheduleScan(), null, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(3));
        }

        private void SaveRules()
        {
            _settings.ButtonRules = ButtonRules.ToList();
            _settings.CheckboxRules = CheckboxRules.ToList();
            _settings.Save();
        }

        public void SavePromptQueue()
        {
            _settings.PromptQueue = PromptQueue.ToList();
            _settings.Save();
        }

        public void ResetPromptQueueToDefault()
        {
            PromptQueue.Clear();
            PromptQueue.Add(DefaultPrompt);
            CurrentPromptIndex = 0;
            IsPromptQueueActive = true;
        }

        // MARK: Scan loop

        private void ScheduleScan()
        {
            if (!IsEnabled) return;
            if (DateTime.Now - _lastActionTime < _cooldown) return;

            var targetApps = AppObserver.Shared.FindTargetApplications();
            if (targetApps.Count == 0)
            {
                // Slow down scan frequency when no target applications are running
                _timer.Change(TimeSpan.FromSeconds(3.5), TimeSpan.FromSeconds(3.5));
                return;
            }

            // Speed up scan frequency (1s) when target applications are active
            _timer.Change(TimeSpan.FromSeconds(1.0), TimeSpan.FromSeconds(1.0));

            List<string> buttons = new();
            List<string> checkboxes = new();
            Application.Current?.Dispatcher.Invoke(() =>
            {
                buttons = ButtonRules.Where(r => r.IsEnabled).Select(r => r.Keyword).ToList();
                checkboxes = CheckboxRules.Where(r => r.IsEnabled).Select(r => r.Keyword).ToList();
            });

            if (buttons.Count == 0) return;

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
                string capturedAppName = "Target App";
                try { capturedAppName = string.IsNullOrEmpty(app.MainWindowTitle) ? app.ProcessName : app.MainWindowTitle; } catch { }

                _ = RunOcrPassAsync(bounds.Value, buttons, capturedApp, capturedAppName);
                break;
            }
        }

        public void Dispose()
        {
            _timer.Dispose();
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
