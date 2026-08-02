using System;
using System.Collections.Specialized;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using NoInteraction.Core;
using NoInteraction.Models;

namespace NoInteraction.UI
{
    public partial class DashboardWindow : Window
    {
        private readonly ApproverEngine _engine = ApproverEngine.Shared;

        public DashboardWindow()
        {
            try
            {
                InitializeComponent();
            }
            catch (Exception ex)
            {
                System.Windows.Forms.MessageBox.Show($"XAML Error: {ex.Message}\n{ex.StackTrace}", "Dashboard XAML Error");
            }

            _engine.PropertyChanged += (_, _) => Dispatcher.Invoke(RefreshHeader);
            _engine.Logs.CollectionChanged += (_, _) => Dispatcher.Invoke(RefreshLog);
            _engine.ButtonRules.CollectionChanged += (_, _) => Dispatcher.Invoke(() => RenderRules(ButtonRulesList, _engine.ButtonRules, TargetType.Button));
            _engine.CheckboxRules.CollectionChanged += (_, _) => Dispatcher.Invoke(() => RenderRules(CheckboxRulesList, _engine.CheckboxRules, TargetType.Checkbox));
            _engine.PromptQueue.CollectionChanged += (_, _) => Dispatcher.Invoke(RenderPromptQueue);
            _engine.TerminalSessions.CollectionChanged += (_, _) => Dispatcher.Invoke(RefreshTerminalSessions);

            // Read straight from the build's own AssemblyVersion instead of a hardcoded
            // string, so this label can never drift out of sync with the version bump
            // build.ps1 applies to the csproj on every build.
            if (VersionBadge != null)
            {
                var v = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
                if (v != null) VersionBadge.Text = $"v{v.Major}.{v.Minor}";
            }

            RefreshHeader();
            RefreshLog();
            RenderRules(ButtonRulesList, _engine.ButtonRules, TargetType.Button);
            RenderRules(CheckboxRulesList, _engine.CheckboxRules, TargetType.Checkbox);
            RenderPromptQueue();
            RefreshTerminalSessions();
        }

        private void RefreshHeader()
        {
            if (EnabledToggle != null) EnabledToggle.IsChecked = _engine.IsEnabled;
            if (StatusText != null) StatusText.Text = _engine.IsEnabled ? "Active & Monitoring Prompts" : "Paused";
            if (ApprovedBadge != null) ApprovedBadge.Text = $"{_engine.TotalApprovalsCount} Approved";
            if (SoundButton != null) SoundButton.Content = _engine.SoundEnabled ? "\U0001F50A" : "\U0001F507";
            if (EngineStatusFooterText != null) EngineStatusFooterText.Text = _engine.IsEnabled ? "Engine Online" : "Monitoring Paused";
            if (StatusDot != null) StatusDot.Fill = _engine.IsEnabled ? new SolidColorBrush(Color.FromRgb(166, 227, 161)) : new SolidColorBrush(Color.FromRgb(243, 139, 168));

            if (PromptQueueToggle != null) PromptQueueToggle.IsChecked = _engine.IsPromptQueueActive;
            if (QueueStatusText != null) QueueStatusText.Text = _engine.IsPromptQueueActive
                ? $"Status: Active — Sending {_engine.CurrentPromptIndex + 1} of {Math.Max(1, _engine.PromptQueue.Count)}"
                : "Status: Paused";

            if (LoopModeToggle != null) LoopModeToggle.IsChecked = _engine.LoopModeEnabled;
            if (LoopCounterText != null) LoopCounterText.Text = $"Dispatched: {_engine.LoopModeCounter} / {(_engine.LoopModeLimit == 0 ? "∞" : _engine.LoopModeLimit.ToString())}";

            if (TerminalMonitoringToggle != null) TerminalMonitoringToggle.IsChecked = _engine.TerminalMonitoringEnabled;
        }

        private void RefreshLog()
        {
            var query = LogSearchBox.Text?.Trim().ToLowerInvariant() ?? "";
            var items = string.IsNullOrEmpty(query)
                ? _engine.Logs
                : _engine.Logs.Where(l =>
                    l.TargetText.ToLowerInvariant().Contains(query) ||
                    l.AppName.ToLowerInvariant().Contains(query) ||
                    l.DetectionMethod.ToLowerInvariant().Contains(query));
            LogListView.ItemsSource = items.ToList();
        }

        private void RenderRules(ItemsControl host, System.Collections.ObjectModel.ObservableCollection<ApprovalRule> rules, TargetType targetType)
        {
            var wrap = new WrapPanel();
            foreach (var rule in rules)
            {
                var chip = new Border
                {
                    CornerRadius = new CornerRadius(12),
                    Background = rule.IsEnabled ? new SolidColorBrush(Color.FromArgb(30, 203, 166, 247)) : new SolidColorBrush(Color.FromArgb(15, 128, 128, 128)),
                    BorderBrush = rule.IsEnabled ? new SolidColorBrush(Color.FromRgb(203, 166, 247)) : new SolidColorBrush(Color.FromRgb(69, 71, 90)),
                    BorderThickness = new Thickness(1),
                    Margin = new Thickness(0, 0, 6, 6),
                    Padding = new Thickness(10, 5, 10, 5)
                };
                var panel = new StackPanel { Orientation = Orientation.Horizontal };

                var toggleBtn = new Button
                {
                    Content = rule.IsEnabled ? "✓" : "○",
                    Padding = new Thickness(2),
                    Margin = new Thickness(0, 0, 6, 0),
                    BorderThickness = new Thickness(0),
                    Background = Brushes.Transparent,
                    Foreground = rule.IsEnabled ? new SolidColorBrush(Color.FromRgb(166, 227, 161)) : new SolidColorBrush(Color.FromRgb(148, 156, 187)),
                    Cursor = System.Windows.Input.Cursors.Hand
                };
                toggleBtn.Click += (_, _) => _engine.ToggleRule(rule.Id, targetType);

                var label = new TextBlock
                {
                    Text = rule.Keyword,
                    VerticalAlignment = VerticalAlignment.Center,
                    TextDecorations = rule.IsEnabled ? null : TextDecorations.Strikethrough,
                    Foreground = rule.IsEnabled ? new SolidColorBrush(Color.FromRgb(205, 214, 244)) : new SolidColorBrush(Color.FromRgb(108, 112, 134)),
                    FontWeight = rule.IsEnabled ? FontWeights.SemiBold : FontWeights.Normal,
                    FontSize = 11.5
                };

                var removeBtn = new Button
                {
                    Content = "✕",
                    Padding = new Thickness(2),
                    Margin = new Thickness(6, 0, 0, 0),
                    BorderThickness = new Thickness(0),
                    Background = Brushes.Transparent,
                    Foreground = new SolidColorBrush(Color.FromRgb(243, 139, 168)),
                    Cursor = System.Windows.Input.Cursors.Hand
                };
                removeBtn.Click += (_, _) => _engine.RemoveRule(rule.Id, targetType);

                panel.Children.Add(toggleBtn);
                panel.Children.Add(label);
                panel.Children.Add(removeBtn);
                chip.Child = panel;
                wrap.Children.Add(chip);
            }
            host.Items.Clear();
            host.Items.Add(wrap);
        }

        private void RenderPromptQueue()
        {
            PromptQueueItemsControl.Items.Clear();
            var stack = new StackPanel();

            for (int i = 0; i < _engine.PromptQueue.Count; i++)
            {
                int index = i;
                var promptText = _engine.PromptQueue[i];

                var border = new Border
                {
                    Background = new SolidColorBrush(Color.FromArgb(15, 255, 255, 255)),
                    CornerRadius = new CornerRadius(6),
                    Padding = new Thickness(10),
                    Margin = new Thickness(0, 0, 0, 8)
                };

                var grid = new Grid();
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                var textPanel = new StackPanel();
                var title = new TextBlock
                {
                    Text = $"Prompt {index + 1}",
                    FontWeight = FontWeights.Bold,
                    FontSize = 11,
                    Foreground = new SolidColorBrush(Color.FromRgb(203, 166, 247))
                };
                var content = new TextBlock
                {
                    Text = promptText,
                    TextWrapping = TextWrapping.Wrap,
                    MaxHeight = 40,
                    FontSize = 10.5,
                    Foreground = new SolidColorBrush(Color.FromRgb(205, 214, 244)),
                    Margin = new Thickness(0, 3, 0, 0)
                };
                textPanel.Children.Add(title);
                textPanel.Children.Add(content);

                var deleteBtn = new Button
                {
                    Content = "🗑",
                    Padding = new Thickness(6, 2, 6, 2),
                    Margin = new Thickness(8, 0, 0, 0),
                    Foreground = new SolidColorBrush(Color.FromRgb(243, 139, 168)),
                    Background = Brushes.Transparent,
                    VerticalAlignment = VerticalAlignment.Center
                };
                deleteBtn.Click += (_, _) =>
                {
                    _engine.PromptQueue.RemoveAt(index);
                };

                Grid.SetColumn(textPanel, 0);
                Grid.SetColumn(deleteBtn, 1);
                grid.Children.Add(textPanel);
                grid.Children.Add(deleteBtn);
                border.Child = grid;
                stack.Children.Add(border);
            }

            PromptQueueItemsControl.Items.Add(stack);
        }

        private void RefreshTerminalSessions()
        {
            TerminalSessionsListView.ItemsSource = _engine.TerminalSessions.ToList();
        }

        private void EnabledToggle_Click(object sender, RoutedEventArgs e) => _engine.IsEnabled = EnabledToggle.IsChecked == true;
        private void SoundButton_Click(object sender, RoutedEventArgs e) => _engine.SoundEnabled = !_engine.SoundEnabled;
        private void ClearLog_Click(object sender, RoutedEventArgs e) => _engine.Logs.Clear();
        private void LogSearchBox_TextChanged(object sender, TextChangedEventArgs e) => RefreshLog();
        private void ResetDefaults_Click(object sender, RoutedEventArgs e) => _engine.ResetRulesToDefault();

        private void AddButtonRule_Click(object sender, RoutedEventArgs e)
        {
            _engine.AddRule(NewButtonKeywordBox.Text, TargetType.Button);
            NewButtonKeywordBox.Text = "";
        }

        private void AddCheckboxRule_Click(object sender, RoutedEventArgs e)
        {
            _engine.AddRule(NewCheckboxKeywordBox.Text, TargetType.Checkbox);
            NewCheckboxKeywordBox.Text = "";
        }

        private void PromptQueueToggle_Click(object sender, RoutedEventArgs e) => _engine.IsPromptQueueActive = PromptQueueToggle.IsChecked == true;
        private void RestartQueue_Click(object sender, RoutedEventArgs e) => _engine.CurrentPromptIndex = 0;

        private void LoopModeToggle_Click(object sender, RoutedEventArgs e) => _engine.LoopModeEnabled = LoopModeToggle.IsChecked == true;
        private void LoopLimitCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_engine != null && LoopLimitCombo != null)
            {
                _engine.LoopModeLimit = LoopLimitCombo.SelectedIndex == 0 ? 0 : 10;
            }
        }
        private void ResetLoop_Click(object sender, RoutedEventArgs e) => _engine.LoopModeCounter = 0;

        private void AddPrompt_Click(object sender, RoutedEventArgs e)
        {
            var text = NewPromptTextBox.Text?.Trim();
            if (!string.IsNullOrEmpty(text))
            {
                _engine.PromptQueue.Add(text);
                NewPromptTextBox.Text = "";
            }
        }

        private void ClearQueue_Click(object sender, RoutedEventArgs e)
        {
            _engine.PromptQueue.Clear();
            _engine.CurrentPromptIndex = 0;
        }

        private void TerminalMonitoringToggle_Click(object sender, RoutedEventArgs e)
        {
            _engine.TerminalMonitoringEnabled = TerminalMonitoringToggle.IsChecked == true;
        }

        private void HideToTray_Click(object sender, RoutedEventArgs e) => Hide();

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        private static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_SHOWWINDOW = 0x0040;

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            var helper = new System.Windows.Interop.WindowInteropHelper(this);
            if (helper.Handle != IntPtr.Zero)
            {
                SetWindowPos(helper.Handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
            }
        }

        protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
        {
            e.Cancel = true;
            Hide();
        }
    }
}
