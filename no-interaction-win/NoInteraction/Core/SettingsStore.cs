using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using NoInteraction.Models;

namespace NoInteraction.Core
{
    /// <summary>
    /// JSON-file settings persistence at %AppData%\NoInteraction\settings.json — the
    /// Windows equivalent of the Mac build's UserDefaults-backed storage.
    /// </summary>
    public sealed class SettingsStore
    {
        public bool IsEnabled { get; set; } = true;
        public bool SoundEnabled { get; set; } = true;
        public int TotalApprovalsCount { get; set; } = 0;
        public List<ApprovalRule> ButtonRules { get; set; } = new();
        public List<ApprovalRule> CheckboxRules { get; set; } = new();

        private static readonly string DirPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "NoInteraction");
        private static readonly string FilePath = Path.Combine(DirPath, "settings.json");

        private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

        public static SettingsStore Load()
        {
            try
            {
                if (File.Exists(FilePath))
                {
                    var json = File.ReadAllText(FilePath);
                    var loaded = JsonSerializer.Deserialize<SettingsStore>(json);
                    if (loaded != null) return loaded;
                }
            }
            catch
            {
                // Corrupt or unreadable settings file — fall back to defaults below.
            }
            return new SettingsStore();
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(DirPath);
                var json = JsonSerializer.Serialize(this, JsonOptions);
                File.WriteAllText(FilePath, json);
            }
            catch
            {
                // Best-effort persistence; a failed save should never crash the scan loop.
            }
        }
    }
}
