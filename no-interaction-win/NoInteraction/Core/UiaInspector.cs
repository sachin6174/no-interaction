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
                foreach (var win in windows) TickCheckboxes(win, 0, checkboxKeywords, PromptRegionOf(win));
            }

            // Pass 2: find & press the first matching approval button
            var allKeywords = buttonKeywords.Concat(checkboxKeywords).ToList();
            foreach (var win in windows)
            {
                var region = PromptRegionOf(win);
                var hasSelection = IsAnyRadioSelected(win, 0, allKeywords, region);
                var result = FindAndPressButton(win, 0, buttonKeywords, hasSelection, region);
                if (result != null) return result;
            }
            return null;
        }

        /// <summary>
        /// Real approval/confirmation prompts in these target apps (Antigravity/Cursor/
        /// VS Code-style agent chat panels) consistently show up in the bottom-right of the
        /// window, right next to the chat's text input box — never in the menu bar, a
        /// sidebar, or a toolbar. Scoping candidate elements to that region is what actually
        /// stops matches on unrelated real buttons elsewhere in the app (a menu's "Run", a
        /// toolbar's "Open", ...) without having to blocklist every possible false positive
        /// by keyword. Deliberately generous (60% of width/height) to tolerate different
        /// panel sizes/dock widths rather than requiring an exact corner.
        /// </summary>
        private Rect? PromptRegionOf(AutomationElement window)
        {
            try
            {
                var bounds = window.Current.BoundingRectangle;
                if (bounds.IsEmpty || bounds.Width <= 0 || bounds.Height <= 0) return null;
                var regionWidth = bounds.Width * 0.6;
                var regionHeight = bounds.Height * 0.6;
                return new Rect(bounds.Right - regionWidth, bounds.Bottom - regionHeight, regionWidth, regionHeight);
            }
            catch
            {
                return null;
            }
        }

        private bool IsInPromptRegion(Point? point, Rect? region)
        {
            // No region computed (e.g. couldn't read window bounds) — fail open rather than
            // silently going blind to every prompt in that window.
            if (region == null) return true;
            if (point == null) return false;
            return region.Value.Contains(point.Value);
        }

        // MARK: Pass 1 — Checkbox ticking

        private void TickCheckboxes(AutomationElement element, int depth, List<string> keywords, Rect? region)
        {
            if (depth > 25) return;
            if (!TryGetControlType(element, out var controlType)) return;
            if (IsIgnoredElement(element, controlType)) return;

            if (controlType == ControlType.CheckBox || controlType == ControlType.RadioButton)
            {
                var label = ElementLabel(element);
                if (keywords.Any(k => KeywordMatcher.Matches(label, k)) && IsInPromptRegion(CenterOf(element), region))
                {
                    if (TryToggleOn(element))
                    {
                        Console.WriteLine($"[UiaInspector] Ticked checkbox/radio '{label}'");
                    }
                }
            }

            foreach (var child in Children(element))
            {
                TickCheckboxes(child, depth + 1, keywords, region);
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

        private InspectionResult? FindAndPressButton(AutomationElement element, int depth, List<string> keywords, bool hasSelection, Rect? region)
        {
            if (depth > 25) return null;
            if (!TryGetControlType(element, out var controlType)) return null;
            if (IsIgnoredElement(element, controlType)) return null;

            // "Strong" roles are natively actionable controls: if their label matches and
            // Invoke isn't wired up, we still trust a blind coordinate click because the
            // control type itself proves it's really a button. "Weak" roles (Custom/Group/
            // Pane/Text/Document/ListItem/Image) exist to catch Electron/Chromium buttons
            // that don't map to a native role — but plenty of ordinary, non-clickable text,
            // panes, and images match those roles too. For those we require proof: only act
            // if TryInvoke (or a selection/toggle pattern) actually succeeds. If it doesn't,
            // that's not a button — keep scanning instead of blind-clicking wherever the
            // matching text happens to be on screen.
            bool isStrongRole =
                controlType == ControlType.Button ||
                controlType == ControlType.SplitButton ||
                controlType == ControlType.RadioButton ||
                controlType == ControlType.Hyperlink ||
                controlType == ControlType.MenuItem;

            bool isWeakRole =
                controlType == ControlType.Custom ||
                controlType == ControlType.Group ||
                controlType == ControlType.Pane ||
                controlType == ControlType.Text ||
                controlType == ControlType.Document ||
                controlType == ControlType.ListItem ||
                controlType == ControlType.Image;

            if (isStrongRole || isWeakRole)
            {
                if (!(controlType == ControlType.RadioButton && hasSelection))
                {
                    var label = ElementLabel(element);
                    // A single generic word (e.g. "Open", "Run", "Yes") must match the WHOLE
                    // label exactly — VS Code's real "Quick Open" command button legitimately
                    // contains "Open" as a whole word, but pressing it opens the command
                    // palette, not an approval dialog. Multi-word phrases ("Always Allow",
                    // "Run Command") are distinctive enough to keep using the more permissive
                    // word-boundary match from KeywordMatcher.
                    var matchedKeyword = (!string.IsNullOrEmpty(label) && label.Length <= 60)
                        ? keywords.FirstOrDefault(k => !string.IsNullOrWhiteSpace(k) && (
                              k.Trim().Contains(' ')
                                  ? KeywordMatcher.Matches(label, k)
                                  : string.Equals(label.Trim(), k.Trim(), StringComparison.OrdinalIgnoreCase)))
                        : null;

                    var center = matchedKeyword != null ? CenterOf(element) : null;

                    // Real approval buttons live bottom-right by the chat input; a text match
                    // anywhere else (menu bar, sidebar, toolbar) is almost certainly an
                    // unrelated button that just happens to share the same word — don't even
                    // attempt invoke on it, just keep walking its children.
                    if (matchedKeyword != null && IsInPromptRegion(center, region))
                    {
                        var display = string.IsNullOrEmpty(label) ? "Approval Button" : label;

                        if (TryInvoke(element))
                        {
                            Console.WriteLine($"[UiaInspector] Invoke/LegacyAction succeeded on '{display}' (role={controlType.ProgrammaticName}, depth={depth})");
                            return new InspectionResult("Invoke", display, center);
                        }
                        if (controlType == ControlType.RadioButton && TrySelect(element))
                        {
                            return new InspectionResult("SelectionItem", display, center);
                        }

                        // Native invoke failed, so we can't prove this element is really
                        // clickable — we're about to guess based on label text alone. A bare
                        // single word like "Run"/"OK"/"Yes" is exactly as likely to be an
                        // ordinary, unrelated button (a toolbar "Run" button, a "Continue
                        // reading" link, ...) as it is a real approval prompt. Only risk the
                        // blind coordinate click for distinctive multi-word phrases ("Always
                        // Allow", "Run Command", "Yes, allow", ...) that are very unlikely to
                        // appear anywhere except an actual confirmation dialog.
                        bool isDistinctiveKeyword = matchedKeyword.Trim().Contains(' ');
                        if (isStrongRole && isDistinctiveKeyword && center.HasValue)
                        {
                            Console.WriteLine($"[UiaInspector] Native invoke failed for '{display}', requesting fallback click at {center}");
                            return new InspectionResult("Fallback Click Needed", display, center);
                        }

                        Console.WriteLine($"[UiaInspector] '{display}' (role={controlType.ProgrammaticName}) matched '{matchedKeyword}' but isn't provably invokable — skipping instead of guessing.");
                    }
                }
            }

            foreach (var child in Children(element))
            {
                var r = FindAndPressButton(child, depth + 1, keywords, hasSelection, region);
                if (r != null) return r;
            }
            return null;
        }

        private bool IsAnyRadioSelected(AutomationElement element, int depth, List<string> keywords, Rect? region)
        {
            if (depth > 25) return false;
            if (!TryGetControlType(element, out var controlType)) return false;
            if (IsIgnoredElement(element, controlType)) return false;

            if (controlType == ControlType.RadioButton || controlType == ControlType.CheckBox)
            {
                var label = ElementLabel(element);
                if (!string.IsNullOrEmpty(label) && keywords.Any(k => KeywordMatcher.Matches(label, k)) && IsInPromptRegion(CenterOf(element), region))
                {
                    if (IsSelectedOrChecked(element)) return true;
                }
            }

            foreach (var child in Children(element))
            {
                if (IsAnyRadioSelected(child, depth + 1, keywords, region)) return true;
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
            catch { }

            try
            {
                if (element.TryGetCurrentPattern(SelectionItemPattern.Pattern, out var selObj))
                {
                    ((SelectionItemPattern)selObj).Select();
                    return true;
                }
            }
            catch { }

            try
            {
                if (element.TryGetCurrentPattern(TogglePattern.Pattern, out var togObj))
                {
                    ((TogglePattern)togObj).Toggle();
                    return true;
                }
            }
            catch { }

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

        /// <summary>Reads direct element label, falling back to recursive child text nodes (needed for
        /// Electron/Chromium web content buttons whose accessible name lives on a child).</summary>
        private string ElementLabel(AutomationElement element)
        {
            string text = "";
            try
            {
                var cur = element.Current;
                text = cur.Name?.Trim() ?? "";
                if (string.IsNullOrEmpty(text)) text = cur.HelpText?.Trim() ?? "";
            }
            catch { text = ""; }

            if (string.IsNullOrEmpty(text))
            {
                text = RecursiveChildText(element, 0);
            }
            return text.Trim();
        }

        private string RecursiveChildText(AutomationElement element, int depth)
        {
            if (depth > 3) return "";
            List<string> parts = new();
            foreach (var child in Children(element))
            {
                string childText = "";
                try
                {
                    var c = child.Current;
                    childText = c.Name?.Trim() ?? "";
                    if (string.IsNullOrEmpty(childText)) childText = c.HelpText?.Trim() ?? "";
                }
                catch { }

                if (!string.IsNullOrEmpty(childText))
                {
                    parts.Add(childText);
                }
                else
                {
                    var deep = RecursiveChildText(child, depth + 1);
                    if (!string.IsNullOrEmpty(deep)) parts.Add(deep);
                }
            }
            return string.Join(" ", parts);
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

