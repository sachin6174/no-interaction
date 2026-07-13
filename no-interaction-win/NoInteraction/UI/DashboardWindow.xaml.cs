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
            InitializeComponent();

            _engine.PropertyChanged += (_, _) => Dispatcher.Invoke(RefreshHeader);
            _engine.Logs.CollectionChanged += (_, _) => Dispatcher.Invoke(RefreshLog);
            _engine.ButtonRules.CollectionChanged += (_, _) => Dispatcher.Invoke(() => RenderRules(ButtonRulesList, _engine.ButtonRules, TargetType.Button));
            _engine.CheckboxRules.CollectionChanged += (_, _) => Dispatcher.Invoke(() => RenderRules(CheckboxRulesList, _engine.CheckboxRules, TargetType.Checkbox));

            RefreshHeader();
            RefreshLog();
            RenderRules(ButtonRulesList, _engine.ButtonRules, TargetType.Button);
            RenderRules(CheckboxRulesList, _engine.CheckboxRules, TargetType.Checkbox);
        }

        private void RefreshHeader()
        {
            EnabledToggle.IsChecked = _engine.IsEnabled;
            StatusText.Text = _engine.IsEnabled ? "Active & Monitoring Prompts" : "Paused";
            ApprovedBadge.Text = $"{_engine.TotalApprovalsCount} Approved";
            SoundButton.Content = _engine.SoundEnabled ? "\U0001F50A" : "\U0001F507";
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

        private void HideToTray_Click(object sender, RoutedEventArgs e) => Hide();

        protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
        {
            // Stay alive in the tray even when the dashboard is closed.
            e.Cancel = true;
            Hide();
        }
    }
}
