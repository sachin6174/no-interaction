using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using NoInteraction.Models;

namespace NoInteraction.Core
{
    /// <summary>
    /// UI Automation equivalent of the Mac build's AXInspector: walks the accessibility
    /// tree of a target process, auto-ticks matching checkboxes, and auto-invokes the
    /// first matching approval button.
    /// </summary>
    public sealed class UiaInspector
    {
        public static readonly UiaInspector Shared = new();
        private UiaInspector() { }

        public sealed class InspectionResult
        {
            public string Action { get; }
            public string ElementText { get; }
            public Point? Position { get; }

            public InspectionResult(string action, string elementText, Point? position)
            {
                Action = action;
                ElementText = elementText;
                Position = position;
            }
        }

        public InspectionResult? InspectAndAutoApprove(Process app, List<string> buttonKeywords, List<string> checkboxKeywords)
        {
            var windows = AppObserver.Shared.GetTopLevelWindows(app);
            if (windows.Count == 0) return null;

            if (AppObserver.Shared.IsBrowser(app))
            {
                var filtered = windows.Where(AppObserver.Shared.IsAntigravityWindow).ToList();
                if (filtered.Count > 0) windows = filtered;
            }

            // Pass 1: auto-tick matching checkboxes across windows
            if (checkboxKeywords.Count > 0)
            {
                foreach (var win in windows) TickCheckboxes(win, 0, checkboxKeywords);
            }

            // Pass 2: find & press the first matching approval button
            var allKeywords = buttonKeywords.Concat(checkboxKeywords).ToList();
            foreach (var win in windows)
            {
                var hasSelection = IsAnyRadioSelected(win, 0, allKeywords);
                var result = FindAndPressButton(win, 0, buttonKeywords, hasSelection);
                if (result != null) return result;
            }
            return null;
        }

        // MARK: Pass 1 — Checkbox ticking

        private void TickCheckboxes(AutomationElement element, int depth, List<string> keywords)
        {
            if (depth > 25) return;
            if (!TryGetControlType(element, out var controlType)) return;
            if (IsIgnoredElement(element, controlType)) return;

            if (controlType == ControlType.CheckBox || controlType == ControlType.RadioButton)
            {
                var label = ElementLabel(element);
                if (keywords.Any(k => KeywordMatcher.Matches(label, k)))
                {
                    if (TryToggleOn(element))
                    {
                        Console.WriteLine($"[UiaInspector] Ticked checkbox/radio '{label}'");
                    }
                }
            }

            foreach (var child in Children(element))
            {
                TickCheckboxes(child, depth + 1, keywords);
            }
        }

        private bool TryToggleOn(AutomationElement element)
        {
            try
            {
                if (element.TryGetCurrentPattern(TogglePattern.Pattern, out var patternObj))
                {
                    var toggle = (TogglePattern)patternObj;
                    if (toggle.Current.ToggleState != ToggleState.On)
                    {
                        toggle.Toggle();
                        return true;
                    }
                    return false;
                }
                if (element.TryGetCurrentPattern(SelectionItemPattern.Pattern, out var selObj))
                {
                    var sel = (SelectionItemPattern)selObj;
                    if (!sel.Current.IsSelected)
                    {
                        sel.Select();
                        return true;
                    }
                }
            }
            catch
            {
                // Element may have become stale between the tree walk and the pattern call.
            }
            return false;
        }

        // MARK: Pass 2 — Button pressing

        private InspectionResult? FindAndPressButton(AutomationElement element, int depth, List<string> keywords, bool hasSelection)
        {
            if (depth > 25) return null;
            if (!TryGetControlType(element, out var controlType)) return null;
            if (IsIgnoredElement(element, controlType)) return null;

            if (controlType == ControlType.Button || controlType == ControlType.SplitButton || controlType == ControlType.RadioButton)
            {
                if (controlType == ControlType.RadioButton && hasSelection) return null;

                var label = ElementLabel(element);
                var isMatch = !string.IsNullOrEmpty(label) && keywords.Any(k => KeywordMatcher.Matches(label, k));

                if (isMatch)
                {
                    var display = string.IsNullOrEmpty(label) ? "Approval Button" : label;
                    var center = CenterOf(element);

                    if (TryInvoke(element))
                    {
                        Console.WriteLine($"[UiaInspector] Invoke succeeded on '{display}' (role={controlType.ProgrammaticName}, depth={depth})");
                        return new InspectionResult("Invoke", display, center);
                    }
                    if (controlType == ControlType.RadioButton && TrySelect(element))
                    {
                        return new InspectionResult("SelectionItem", display, center);
                    }
                    if (center.HasValue)
                    {
                        Console.WriteLine($"[UiaInspector] Invoke failed for '{display}', requesting fallback click at {center}");
                        return new InspectionResult("Fallback Click Needed", display, center);
                    }
                }
            }

            foreach (var child in Children(element))
            {
                var r = FindAndPressButton(child, depth + 1, keywords, hasSelection);
                if (r != null) return r;
            }
            return null;
        }

        private bool IsAnyRadioSelected(AutomationElement element, int depth, List<string> keywords)
        {
            if (depth > 25) return false;
            if (!TryGetControlType(element, out var controlType)) return false;
            if (IsIgnoredElement(element, controlType)) return false;

            if (controlType == ControlType.RadioButton || controlType == ControlType.CheckBox)
            {
                var label = ElementLabel(element);
                if (!string.IsNullOrEmpty(label) && keywords.Any(k => KeywordMatcher.Matches(label, k)))
                {
                    if (IsSelectedOrChecked(element)) return true;
                }
            }

            foreach (var child in Children(element))
            {
                if (IsAnyRadioSelected(child, depth + 1, keywords)) return true;
            }
            return false;
        }

        private bool TryInvoke(AutomationElement element)
        {
            try
            {
                if (element.TryGetCurrentPattern(InvokePattern.Pattern, out var patternObj))
                {
                    ((InvokePattern)patternObj).Invoke();
                    return true;
                }
            }
            catch
            {
                // Falls through to selection/fallback-click handling below.
            }
            return false;
        }

        private bool TrySelect(AutomationElement element)
        {
            try
            {
                if (element.TryGetCurrentPattern(SelectionItemPattern.Pattern, out var patternObj))
                {
                    ((SelectionItemPattern)patternObj).Select();
                    return true;
                }
            }
            catch { }
            return false;
        }

        private bool IsSelectedOrChecked(AutomationElement element)
        {
            try
            {
                if (element.TryGetCurrentPattern(TogglePattern.Pattern, out var toggleObj))
                    return ((TogglePattern)toggleObj).Current.ToggleState == ToggleState.On;
                if (element.TryGetCurrentPattern(SelectionItemPattern.Pattern, out var selObj))
                    return ((SelectionItemPattern)selObj).Current.IsSelected;
            }
            catch { }
            return false;
        }

        // MARK: Helpers

        private bool IsIgnoredElement(AutomationElement element, ControlType controlType)
        {
            if (controlType == ControlType.Tree || controlType == ControlType.DataGrid || controlType == ControlType.Tab)
                return true;

            string name, help;
            try
            {
                name = element.Current.Name?.ToLowerInvariant() ?? "";
                help = element.Current.HelpText?.ToLowerInvariant() ?? "";
            }
            catch { return true; }

            string[] blocked = { "sidebar", "explorer", "outline", "navigation", "tab bar" };
            return blocked.Any(b => name.Contains(b) || help.Contains(b));
        }

        private bool TryGetControlType(AutomationElement element, out ControlType controlType)
        {
            try
            {
                controlType = element.Current.ControlType;
                return true;
            }
            catch
            {
                controlType = ControlType.Custom;
                return false;
            }
        }

        /// <summary>Reads the element's Name, falling back to child Text nodes (needed for
        /// Electron/Chromium web content buttons whose accessible name lives on a child).</summary>
        private string ElementLabel(AutomationElement element)
        {
            string text;
            try { text = element.Current.Name?.Trim() ?? ""; }
            catch { text = ""; }

            if (string.IsNullOrEmpty(text))
            {
                foreach (var child in Children(element))
                {
                    if (!TryGetControlType(child, out var ct)) continue;
                    if (ct == ControlType.Text)
                    {
                        string childText;
                        try { childText = child.Current.Name?.Trim() ?? ""; }
                        catch { childText = ""; }
                        if (!string.IsNullOrEmpty(childText))
                        {
                            text = text.Length == 0 ? childText : text + " " + childText;
                        }
                    }
                }
            }
            return text.Trim();
        }

        private List<AutomationElement> Children(AutomationElement element)
        {
            var result = new List<AutomationElement>();
            try
            {
                var children = element.FindAll(TreeScope.Children, System.Windows.Automation.Condition.TrueCondition);
                foreach (AutomationElement child in children) result.Add(child);
            }
            catch
            {
                // Stale/torn-down elements throw ElementNotAvailableException; treat as leaf.
            }
            return result;
        }

        public Point? CenterOf(AutomationElement element)
        {
            try
            {
                var rect = element.Current.BoundingRectangle;
                if (rect.IsEmpty || rect.Width <= 0 || rect.Height <= 0) return null;
                return new Point(rect.X + rect.Width / 2, rect.Y + rect.Height / 2);
            }
            catch
            {
                return null;
            }
        }
    }
}
